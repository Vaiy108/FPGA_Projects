
--  OV7670 + AL422B FIFO -> 80x60x4-bit Frame Buffer -> VGA 640x480
--  Target : Spartan-6 Mimas V2, 100 MHz system clock
--
--  FRAME BUFFER: 80 x 60 x 4 bits = 4800 nibbles = 2400 bytes = ~2 BRAMs
--  Address: row*80 + col,  range 0..4799
--
--  CAPTURE: subsample 4:1 horizontally and 4:1 vertically
--    store pixel at col_cnt=0,4,8,...,316  (every 4th pixel = 80 pixels/line)
--    store line  at row_cnt=0,4,8,...,236  (every 4th line  = 60 lines)
--
--  DISPLAY: each stored pixel -> 8x8 block on 640x480 VGA
--    col = h_cnt / 8   (0..79)
--    row = v_cnt / 8   (0..59)
--    addr = row*80 + col  (0..4799)
--
--  LUMA: shift-add approximation, zero multipliers:
--    Y ~ (r5<<3) + (g6<<3) + (b5<<2)   max=876, top 4 bits = pixel
-- ===========================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity cam_fifo_bringup is
    port (
        clk_100mhz : in    std_logic;
        cam_d      : in    std_logic_vector(7 downto 0);
        cam_rclk   : out   std_logic;
        cam_oe     : out   std_logic;
        cam_rrst   : out   std_logic;
        cam_sioc   : out   std_logic;
        cam_siod   : inout std_logic;
        cam_wrst   : out   std_logic;
        cam_wr     : out   std_logic;
        vga_hsync  : out   std_logic;
        vga_vsync  : out   std_logic;
        vga_r      : out   std_logic_vector(2 downto 0);
        vga_g      : out   std_logic_vector(2 downto 0);
        vga_b      : out   std_logic_vector(1 downto 0);
        cam_vsy    : in    std_logic;
        cam_href   : in    std_logic;
        led        : out   std_logic_vector(7 downto 0)
    );
end entity;

architecture rtl of cam_fifo_bringup is

    -- VGA timing constants (640x480 @ 60Hz, 25MHz pixel clock)
    constant H_ACTIVE : integer := 640;
    constant H_FP     : integer := 16;
    constant H_SYNC   : integer := 96;
    constant H_TOTAL  : integer := 800;
    constant V_ACTIVE : integer := 480;
    constant V_FP     : integer := 10;
    constant V_SYNC   : integer := 2;
    constant V_TOTAL  : integer := 525;

    signal clk_div    : unsigned(1 downto 0) := (others => '0');
    signal pixel_tick : std_logic            := '0';
    signal h_cnt      : unsigned(9 downto 0) := (others => '0');
    signal v_cnt      : unsigned(9 downto 0) := (others => '0');

    signal startup_cnt : unsigned(23 downto 0) := (others => '0');
    signal init_done   : std_logic             := '0';
    signal sccb_done   : std_logic             := '0';

    signal oe_reg   : std_logic := '1';
    signal wrst_reg : std_logic := '1';
    signal rrst_reg : std_logic := '1';
    signal rclk_reg : std_logic := '0';

    -- Camera synchronisers
    signal href_meta : std_logic := '0';
    signal href_sync : std_logic := '0';
    signal href_d    : std_logic := '0';
    signal vsy_meta  : std_logic := '0';
    signal vsy_sync  : std_logic := '0';
    signal vsy_d     : std_logic := '0';
    signal href_fe   : std_logic := '0';
    signal vsy_fe    : std_logic := '0';

    -- WRST held inactive after startup

    -- ---------------
    --  Frame buffer: 80 x 60 x 4 bits = 4800 nibbles
    --  80 = 2^6 + 2^4, row*80 = (row<<6)+(row<<4), no multiplier
    --  Fits in ~2 BRAMs, well within XC6SLX9 budget of 32
    -- -----------------------------------------------------------------------
    type framebuf_t is array (0 to 4799) of std_logic_vector(3 downto 0);
    signal framebuf : framebuf_t;
    attribute ram_style            : string;
    attribute ram_style of framebuf : signal is "block";

    signal fb_wr_addr : unsigned(12 downto 0) := (others => '0');  -- 0..4799
    signal fb_wr_en   : std_logic             := '0';
    signal fb_wr_data : std_logic_vector(3 downto 0) := (others => '0');

    -- Readback FSM
    type rd_t is (RD_IDLE, RD_RRST, RD_WAIT_FE, RD_READ);
    signal rd_state   : rd_t                 := RD_IDLE;
    signal rrst_cnt   : unsigned(4 downto 0) := (others => '0');
    signal byte_phase : unsigned(2 downto 0) := (others => '0');
    signal byte_sel   : std_logic            := '0';
    signal byte0_reg  : std_logic_vector(7 downto 0) := (others => '0');
    -- col_cnt counts pixels 0..319, row_cnt counts lines 0..239
    signal col_cnt    : unsigned(8 downto 0) := (others => '0');
    signal row_cnt    : unsigned(7 downto 0) := (others => '0');
    -- fb_col and fb_row are the subsampled write coordinates (0..79, 0..59)
    signal fb_col     : unsigned(6 downto 0) := (others => '0');  -- 0..79
    signal fb_row     : unsigned(5 downto 0) := (others => '0');  -- 0..59
    signal dbg_byte   : std_logic_vector(3 downto 0) := (others => '0');

    -- SCCB
    signal sccb_div  : unsigned(9 downto 0) := (others => '0');
    signal tick_sccb : std_logic            := '0';
    signal sioc_reg  : std_logic            := '1';
    signal siod_out  : std_logic            := '1';
    signal siod_oe   : std_logic            := '1';

    type sccb_t is (
        S_WAIT, S_START_A, S_START_B,
        S_BIT_LO, S_BIT_HI, S_DC_LO, S_DC_HI,
        S_STOP_A, S_STOP_B, S_GAP, S_DONE);
    signal sccb_state : sccb_t := S_WAIT;

    type rom_t is array (0 to 35) of std_logic_vector(7 downto 0);
    constant INIT_ROM : rom_t := (
        x"42", x"12", x"80",   -- 0: soft reset
        x"42", x"11", x"00",   -- 1: CLKRC prescaler off
        x"42", x"12", x"14",   -- 2: QVGA + RGB mode
        x"42", x"0C", x"04",   -- 3: COM3
        x"42", x"3E", x"00",   -- 4: COM14
        x"42", x"70", x"3A",   -- 5: scaling
        x"42", x"71", x"35",   -- 6: scaling
        x"42", x"8C", x"00",   -- 7: RGB444 off
        x"42", x"40", x"D0",   -- 8: COM15 RGB565 full range
        x"42", x"3A", x"04",   -- 9: TSLB
        x"42", x"15", x"02",   -- 10: COM10 VSYNC active low
        x"42", x"55", x"00"    -- 11: brightness
    );
    constant NUM_WRITES : integer := 12;

    signal rom_ptr   : integer range 0 to 37 := 0;
    signal wr_cnt    : integer range 0 to 12 := 0;
    signal bsel      : integer range 0 to 2  := 0;
    signal bit_idx   : integer range 0 to 7  := 7;
    signal tx_byte   : std_logic_vector(7 downto 0) := x"42";
    signal sccb_gap  : unsigned(19 downto 0)        := (others => '0');
    signal sccb_long : std_logic                    := '0';

    -- Diagnostic latches
    signal vsy_seen   : std_logic := '0';
    signal href_seen  : std_logic := '0';
    signal frame_done : std_logic := '0';

begin

    cam_oe   <= oe_reg;
    cam_wrst <= wrst_reg;
    cam_rrst <= rrst_reg;
    cam_rclk <= rclk_reg;
    cam_wr   <= '1';
    cam_sioc <= sioc_reg;
    cam_siod <= '0' when (siod_oe = '1' and siod_out = '0') else 'Z';

    vga_hsync <= '0' when (h_cnt >= to_unsigned(H_ACTIVE + H_FP, 10) and
                           h_cnt <  to_unsigned(H_ACTIVE + H_FP + H_SYNC, 10))
                     else '1';
    vga_vsync <= '0' when (v_cnt >= to_unsigned(V_ACTIVE + V_FP, 10) and
                           v_cnt <  to_unsigned(V_ACTIVE + V_FP + V_SYNC, 10))
                     else '1';

    -- -----------------------------------------------------------------------
    --  LED diagnostics - read these left to right D1..D8
    --
    --  D1 = init_done      : solid ON after 50ms startup
    --  D2 = sccb_done      : solid ON after all 12 SCCB writes complete (~6s)
    --  D3 = vsy_seen       : latches ON when first VSYNC falling edge seen
    --  D4 = href_seen      : latches ON when first HREF falling edge seen
    --  D5 = rd_active      : ON when FSM is in RD_READ or RD_WAIT_FE
    --  D6 = frame_done     : latches ON when first full frame written (row 59 reached)
    --  D7 = vsy_sync live  : solid ON expected (active-low VSYNC = high most of time)
    --  D8 = href_fe_seen   : latches ON if HREF falling edge ever seen (should be ON)
    --                        if OFF: HREF never falls = stuck HIGH or pull-up missing
    -- -----------------------------------------------------------------------

    led(0) <= init_done;
    led(1) <= sccb_done;
    led(2) <= vsy_seen;
    led(3) <= href_seen;
    led(4) <= '1' when (rd_state = RD_READ or rd_state = RD_WAIT_FE) else '0';
    led(5) <= frame_done;
    led(6) <= vsy_sync;
    led(7) <= href_sync;  -- solid ON = HREF stuck HIGH (bad); flickering = OK

    
    --  Diagnostic latches
    -- -----------------------------------------------------------------------
    process(clk_100mhz)
    begin
        if rising_edge(clk_100mhz) then
            if vsy_fe = '1' then
                vsy_seen <= '1';
            end if;
            if href_fe = '1' then
                href_seen <= '1';
            end if;
            if rd_state = RD_WAIT_FE and
               row_cnt = to_unsigned(239, 8) then
                frame_done <= '1';
            end if;
        end if;
    end process;

    
    --  Pixel clock: 100 MHz / 4 = 25 MHz
    -- -----------------------------------------------------------------------
    process(clk_100mhz)
    begin
        if rising_edge(clk_100mhz) then
            pixel_tick <= '0';
            if clk_div = "11" then
                clk_div    <= (others => '0');
                pixel_tick <= '1';
            else
                clk_div <= clk_div + 1;
            end if;
        end if;
    end process;

    
    --  VGA counters
    -- -----------------------------------------------------------------------
    process(clk_100mhz)
    begin
        if rising_edge(clk_100mhz) then
            if pixel_tick = '1' then
                if h_cnt = to_unsigned(H_TOTAL - 1, 10) then
                    h_cnt <= (others => '0');
                    if v_cnt = to_unsigned(V_TOTAL - 1, 10) then
                        v_cnt <= (others => '0');
                    else
                        v_cnt <= v_cnt + 1;
                    end if;
                else
                    h_cnt <= h_cnt + 1;
                end if;
            end if;
        end if;
    end process;

    
    --  Startup: hold OE high for 50 ms then release
    -- -----------------------------------------------------------------------
    process(clk_100mhz)
    begin
        if rising_edge(clk_100mhz) then
            if startup_cnt < to_unsigned(5_000_000, 24) then
                startup_cnt <= startup_cnt + 1;
                oe_reg    <= '1';
                init_done <= '0';
            else
                oe_reg    <= '0';
                init_done <= '1';
            end if;
        end if;
    end process;

    
    --  Camera synchronisers (two-FF metastability)
    -- -----------------------------------------------------------------------
    process(clk_100mhz)
    begin
        if rising_edge(clk_100mhz) then
            href_meta <= cam_href;  href_sync <= href_meta;  href_d <= href_sync;
            vsy_meta  <= cam_vsy;   vsy_sync  <= vsy_meta;   vsy_d  <= vsy_sync;
            href_fe   <= href_d and not href_sync;
            vsy_fe    <= vsy_d  and not vsy_sync;
        end if;
    end process;

    -- WRST held inactive (high) permanently after startup
    -- Pulsing WRST on every VSYNC was destabilising the camera
    wrst_reg <= '1';

    
    --  Frame buffer write port (synchronous BRAM)
    -- -----------------------------------------------------------------------
    process(clk_100mhz)
    begin
        if rising_edge(clk_100mhz) then
            if fb_wr_en = '1' then
                framebuf(to_integer(fb_wr_addr)) <= fb_wr_data;
            end if;
        end if;
    end process;

    -- -----------------------------------------------------------------------
    --  FIFO readback -> frame buffer (80x60 subsampled)
    --
    --  col_cnt: pixel index within line, 0..319 (full QVGA width)
    --  row_cnt: line index within frame,  0..239 (full QVGA height)
    --  fb_col = col_cnt >> 2  (0..79)   stored as col_cnt(8 downto 2)
    --  fb_row = row_cnt >> 2  (0..59)   stored as row_cnt(7 downto 2)
    --
    --  Only write to framebuffer when col_cnt(1:0)=00 AND row_cnt(1:0)=00
    --  i.e. every 4th pixel on every 4th line
    --
    --  Address = fb_row * 80 + fb_col
    --  80 = 64 + 16, so fb_row*80 = (fb_row<<6)+(fb_row<<4)  -- no multiplier
    -- -----------------------------------------------------------------------
    process(clk_100mhz)
        variable r5   : unsigned(4 downto 0);
        variable g6   : unsigned(5 downto 0);
        variable b5   : unsigned(4 downto 0);
        variable r8   : unsigned(7 downto 0);
        variable g8   : unsigned(7 downto 0);
        variable b8   : unsigned(7 downto 0);
        variable acc  : unsigned(17 downto 0);
        variable gray : unsigned(7 downto 0);
        variable addr : unsigned(12 downto 0);
    begin
        if rising_edge(clk_100mhz) then
            rrst_reg <= '1';
            rclk_reg <= '0';
            fb_wr_en <= '0';

            case rd_state is

                when RD_IDLE =>
                    if sccb_done = '1' and vsy_fe = '1' then
                        rrst_reg   <= '0';
                        rrst_cnt   <= to_unsigned(16, 5);
                        byte_phase <= (others => '0');
                        row_cnt    <= (others => '0');
                        col_cnt    <= (others => '0');
                        rd_state   <= RD_RRST;
                    end if;

                when RD_RRST =>
                    rrst_reg   <= '0';
                    byte_phase <= byte_phase + 1;
                    if byte_phase < to_unsigned(4, 3) then
                        rclk_reg <= '1';
                    end if;
                    if byte_phase = to_unsigned(7, 3) then
                        byte_phase <= (others => '0');
                    end if;
                    if rrst_cnt /= 0 then
                        rrst_cnt <= rrst_cnt - 1;
                    else
                        rrst_reg <= '1';
                        rd_state <= RD_WAIT_FE;
                    end if;

                when RD_WAIT_FE =>
                    if href_fe = '1' then
                        byte_phase <= (others => '0');
                        byte_sel   <= '0';
                        col_cnt    <= (others => '0');
                        rd_state   <= RD_READ;
                    end if;
                    if vsy_fe = '1' then
                        row_cnt    <= (others => '0');
                        col_cnt    <= (others => '0');
                        rrst_reg   <= '0';
                        rrst_cnt   <= to_unsigned(16, 5);
                        byte_phase <= (others => '0');
                        rd_state   <= RD_RRST;
                    end if;

                when RD_READ =>
                    byte_phase <= byte_phase + 1;
                    if byte_phase < to_unsigned(4, 3) then
                        rclk_reg <= '1';
                    end if;

                    if byte_phase = to_unsigned(7, 3) then
                        byte_phase <= (others => '0');

                        if byte_sel = '0' then
                            byte0_reg <= cam_d;
                            byte_sel  <= '1';
                        else
                            -- Decode RGB565 -> 8-bit luma (BT.601)
                            r5 := unsigned(byte0_reg(7 downto 3));
                            g6 := unsigned(byte0_reg(2 downto 0)) &
                                  unsigned(cam_d(7 downto 5));
                            b5 := unsigned(cam_d(4 downto 0));
                            -- Expand to 8-bit
                            r8 := r5 & r5(4 downto 2);
                            g8 := g6 & g6(5 downto 4);
                            b8 := b5 & b5(4 downto 2);
                            -- BT.601: Y = R*77 + G*150 + B*29 (>> 8)
                            acc  := resize(r8 * to_unsigned(77,  8), 18)
                                  + resize(g8 * to_unsigned(150, 8), 18)
                                  + resize(b8 * to_unsigned(29,  8), 18);
                            gray := acc(15 downto 8);

                            byte_sel <= '0';

                            -- Subsample: write only every 4th pixel on every 4th line
                            -- col_cnt(1:0)=00  means pixel 0,4,8,...,316
                            -- row_cnt(1:0)=00  means line  0,4,8,...,236
                            if col_cnt(1 downto 0) = "00" and
                               row_cnt(1 downto 0) = "00" then
                                -- fb_col = col_cnt>>2 (0..79)
                                -- fb_row = row_cnt>>2 (0..59)
                                -- addr = fb_row*80 + fb_col
                                -- 80 = 64+16, so row*80 = (row<<6)+(row<<4)
                                fb_col <= col_cnt(8 downto 2);
                                fb_row <= row_cnt(7 downto 2);
                                addr := shift_left(resize(row_cnt(7 downto 2), 13), 6)
                                      + shift_left(resize(row_cnt(7 downto 2), 13), 4)
                                      + resize(col_cnt(8 downto 2), 13);
                                fb_wr_addr <= addr;
                                fb_wr_data <= std_logic_vector(gray(7 downto 4));
                                fb_wr_en   <= '1';
                                dbg_byte   <= std_logic_vector(gray(7 downto 4));
                            end if;

                            if col_cnt = to_unsigned(319, 9) then
                                -- End of line: always go back to wait for next HREF
                                -- vsy_fe handler in RD_WAIT_FE will restart the frame
                                row_cnt  <= row_cnt + 1;  -- wraps at 255, harmless
                                rd_state <= RD_WAIT_FE;
                            else
                                col_cnt <= col_cnt + 1;
                            end if;
                        end if;
                    end if;

                    if vsy_fe = '1' then
                        row_cnt    <= (others => '0');
                        col_cnt    <= (others => '0');
                        rrst_reg   <= '0';
                        rrst_cnt   <= to_unsigned(16, 5);
                        byte_phase <= (others => '0');
                        rd_state   <= RD_RRST;
                    end if;

            end case;
        end if;
    end process;

    
    --  VGA pixel output: read frame buffer, output grayscale
    --  col = h_cnt / 8  (0..79)   -> h_cnt(9:3)
    --  row = v_cnt / 8  (0..59)   -> v_cnt(9:3)
    --  addr = row*80 + col  = (row<<6)+(row<<4)+col  (no multiplier)
    -- -----------------------------------------------------------------------
    process(clk_100mhz)
        variable col9 : integer range 0 to 79;
        variable row9 : integer range 0 to 59;
        variable addr : integer range 0 to 4799;
        variable pix4 : std_logic_vector(3 downto 0);
        variable pix8 : std_logic_vector(7 downto 0);
    begin
        if rising_edge(clk_100mhz) then
            if pixel_tick = '1' then
                pix8 := (others => '0');
                if h_cnt < to_unsigned(H_ACTIVE, 10) and
                   v_cnt < to_unsigned(V_ACTIVE, 10) then
                    col9 := to_integer(h_cnt) / 8;   -- 0..79
                    row9 := to_integer(v_cnt) / 8;   -- 0..59
                    addr := row9 * 80 + col9;         -- 0..4799
                    pix4 := framebuf(addr);
                    pix8 := pix4 & pix4;
                end if;
                vga_r <= pix8(7 downto 5);
                vga_g <= pix8(7 downto 5);
                vga_b <= pix8(7 downto 6);
            end if;
        end if;
    end process;

    
    --  SCCB 100 kHz tick
    -- -----------------------------------------------------------------------
    process(clk_100mhz)
    begin
        if rising_edge(clk_100mhz) then
            tick_sccb <= '0';
            if sccb_div = to_unsigned(999, 10) then
                sccb_div  <= (others => '0');
                tick_sccb <= '1';
            else
                sccb_div <= sccb_div + 1;
            end if;
        end if;
    end process;

    
    --  SCCB FSM
    -- -----------------------------------------------------------------------
    process(clk_100mhz)
    begin
        if rising_edge(clk_100mhz) then
            if tick_sccb = '1' then
                case sccb_state is
                    when S_WAIT =>
                        sioc_reg <= '1'; siod_out <= '1'; siod_oe <= '1';
                        if init_done = '1' then
                            -- SCCB BYPASSED FOR TESTING - camera runs on default settings
                            sccb_done  <= '1';
                            sccb_state <= S_DONE;
                        end if;
                    when S_START_A =>
                        sioc_reg <= '1'; siod_out <= '1'; siod_oe <= '1';
                        sccb_state <= S_START_B;
                    when S_START_B =>
                        sioc_reg <= '1'; siod_out <= '0'; siod_oe <= '1';
                        sccb_state <= S_BIT_LO;
                    when S_BIT_LO =>
                        sioc_reg <= '0'; siod_out <= tx_byte(bit_idx);
                        siod_oe  <= '1'; sccb_state <= S_BIT_HI;
                    when S_BIT_HI =>
                        sioc_reg <= '1';
                        if bit_idx = 0 then sccb_state <= S_DC_LO;
                        else bit_idx <= bit_idx-1; sccb_state <= S_BIT_LO;
                        end if;
                    when S_DC_LO =>
                        sioc_reg <= '0'; siod_out <= '1'; siod_oe <= '0';
                        sccb_state <= S_DC_HI;
                    when S_DC_HI =>
                        sioc_reg <= '1'; siod_oe <= '1';
                        if bsel < 2 then
                            bsel <= bsel+1; rom_ptr <= rom_ptr+1;
                            tx_byte <= INIT_ROM(rom_ptr+1); bit_idx <= 7;
                            sccb_state <= S_BIT_LO;
                        else sccb_state <= S_STOP_A;
                        end if;
                    when S_STOP_A =>
                        sioc_reg <= '0'; siod_out <= '0'; siod_oe <= '1';
                        sccb_state <= S_STOP_B;
                    when S_STOP_B =>
                        sioc_reg <= '1'; siod_out <= '1'; siod_oe <= '1';
                        if wr_cnt = 0 then sccb_long <= '1';
                        else sccb_long <= '0'; end if;
                        sccb_gap <= (others => '0'); sccb_state <= S_GAP;
                    when S_GAP =>
                        if sccb_long = '1' then
                            if sccb_gap < to_unsigned(50000, 20) then
                                sccb_gap <= sccb_gap + 1;
                            else
                                sccb_gap  <= (others=>'0'); sccb_long <= '0';
                                rom_ptr   <= rom_ptr + 1;
                                if wr_cnt < NUM_WRITES-1 then
                                    wr_cnt <= wr_cnt+1; bsel <= 0;
                                    tx_byte <= INIT_ROM(rom_ptr+1); bit_idx <= 7;
                                    sccb_state <= S_START_A;
                                else sccb_done<='1'; sccb_state<=S_DONE;
                                end if;
                            end if;
                        else
                            if sccb_gap < to_unsigned(500, 20) then
                                sccb_gap <= sccb_gap + 1;
                            else
                                sccb_gap <= (others=>'0');
                                rom_ptr  <= rom_ptr + 1;
                                if wr_cnt < NUM_WRITES-1 then
                                    wr_cnt <= wr_cnt+1; bsel <= 0;
                                    tx_byte <= INIT_ROM(rom_ptr+1); bit_idx <= 7;
                                    sccb_state <= S_START_A;
                                else sccb_done<='1'; sccb_state<=S_DONE;
                                end if;
                            end if;
                        end if;
                    when S_DONE =>
                        sioc_reg<='1'; siod_out<='1'; siod_oe<='1';
                        sccb_done<='1';
                end case;
            end if;
        end if;
    end process;

end architecture;