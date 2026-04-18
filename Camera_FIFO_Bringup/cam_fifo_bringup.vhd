-- ===========================================================================
--  OV7670 + AL422B FIFO -> 320x240x4-bit Frame Buffer -> VGA 640x480
--  Target : Spartan-6 Mimas V2, 100 MHz system clock
--
--  FRAME BUFFER: 320 x 240 x 4 bits = 38,400 bytes = 17 BRAMs
--  Address: row*320 + col,  range 0..76799
--  Pixel: 4-bit grayscale (16 shades), expanded to 8-bit for VGA output
--
--  WRITE SIDE (camera):
--    On each HREF falling edge: read 640 bytes from FIFO = 320 RGB565 pixels
--    Convert to 4-bit grayscale, write to frame buffer at current row address
--    Row increments on line done (col_cnt = 319), resets on VSYNC
--
--  READ SIDE (VGA):
--    col = h_cnt / 8  (0..319, 8x horizontal scaling)
--    row = v_cnt / 8  (0..239, 8x vertical scaling)
--    pixel = framebuf(row*320 + col), expanded: pix8 = pix4 & pix4
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

    constant H_ACTIVE : integer := 640;
    constant H_FP     : integer := 16;
    constant H_SYNC   : integer := 96;
    constant H_BP     : integer := 48;
    constant H_TOTAL  : integer := 800;
    constant V_ACTIVE : integer := 480;
    constant V_FP     : integer := 10;
    constant V_SYNC   : integer := 2;
    constant V_BP     : integer := 33;
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

    -- Camera synchronisers (two-FF metastability removal)
    signal href_meta : std_logic := '0';
    signal href_sync : std_logic := '0';
    signal href_d    : std_logic := '0';
    signal vsy_meta  : std_logic := '0';
    signal vsy_sync  : std_logic := '0';
    signal vsy_d     : std_logic := '0';
    signal href_fe   : std_logic := '0';  -- HREF falling edge (registered)
    signal vsy_fe    : std_logic := '0';  -- VSYNC falling edge (registered)

    -- WRST
    signal wrst_cnt  : unsigned(4 downto 0) := (others => '0');
    signal wrst_busy : std_logic            := '0';

    -- -----------------------------------------------------------------------
    --  Full frame buffer: 320 x 240 x 4 bits
    --  17 BRAMs on XC6SLX9 (budget: 32)
    -- -----------------------------------------------------------------------
--    type framebuf_t is array (0 to 76799) of std_logic_vector(3 downto 0);
--    signal framebuf : framebuf_t;
	 type framebuf_t is array (0 to 4799) of std_logic_vector(3 downto 0);
    signal framebuf : framebuf_t;
    attribute ram_style            : string;
    attribute ram_style of framebuf : signal is "block";

    signal fb_wr_addr : integer range 0 to 76799 := 0;
    signal fb_wr_row  : integer range 0 to 239   := 0;
    signal fb_wr_col  : integer range 0 to 319   := 0;
    signal fb_wr_en   : std_logic                := '0';
    signal fb_wr_data : std_logic_vector(3 downto 0) := (others => '0');

    -- Readback FSM
    type rd_t is (RD_IDLE, RD_RRST, RD_WAIT_FE, RD_READ);
    signal rd_state   : rd_t                := RD_IDLE;
    signal rrst_cnt   : unsigned(4 downto 0):= (others => '0');
    signal byte_phase : unsigned(2 downto 0):= (others => '0');
    signal byte_sel   : std_logic           := '0';
    signal byte0_reg  : std_logic_vector(7 downto 0) := (others => '0');
    signal col_cnt    : unsigned(8 downto 0):= (others => '0');
    signal row_cnt    : unsigned(7 downto 0):= (others => '0');
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

    led(0) <= init_done;
    led(1) <= sccb_done;
    led(2) <= not vsy_sync;
    led(3) <= href_sync;
    led(4) <= '1' when rd_state = RD_READ    else '0';
    led(5) <= '1' when rd_state = RD_WAIT_FE else '0';
    led(6) <= '1' when rd_state = RD_RRST    else '0';
    led(7) <= dbg_byte(3);

    -- -----------------------------------------------------------------------
    --  Pixel clock (100 MHz / 4 = 25 MHz)
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

    -- -----------------------------------------------------------------------
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

    -- -----------------------------------------------------------------------
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

    -- -----------------------------------------------------------------------
    --  Camera input synchronisers
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

    -- -----------------------------------------------------------------------
    --  WRST: pulse low for 16 clocks on each VSYNC (after SCCB done)
    -- -----------------------------------------------------------------------
    process(clk_100mhz)
    begin
        if rising_edge(clk_100mhz) then
            wrst_reg <= '1';
            if vsy_fe = '1' and sccb_done = '1' then
                wrst_cnt  <= to_unsigned(16, 5);
                wrst_busy <= '1';
            end if;
            if wrst_busy = '1' then
                wrst_reg <= '0';
                if wrst_cnt /= 0 then
                    wrst_cnt <= wrst_cnt - 1;
                else
                    wrst_busy <= '0';
                end if;
            end if;
        end if;
    end process;

    -- -----------------------------------------------------------------------
    --  Frame buffer write port (synchronous BRAM)
    -- -----------------------------------------------------------------------
    process(clk_100mhz)
    begin
        if rising_edge(clk_100mhz) then
            if fb_wr_en = '1' then
                framebuf(fb_wr_addr) <= fb_wr_data;
            end if;
        end if;
    end process;

    -- -----------------------------------------------------------------------
    --  FIFO readback -> frame buffer
    --
    --  Timing: 8 system clocks per byte (80 ns), RCLK high for first 4
    --  Camera writes at ~83 ns/byte (12 MHz / 2 for RGB565)
    --  We read slightly slower, so the FIFO naturally fills ahead of us
    --
    --  FSM:
    --   RD_IDLE   : wait for sccb_done and first VSYNC falling edge
    --   RD_RRST   : pulse RRST low for 16 RCLK cycles to reset FIFO pointer
    --   RD_WAIT_FE: wait for HREF falling edge (line just completed writing)
    --   RD_READ   : read 640 bytes, decode each pair to 4-bit gray,
    --               write to framebuf; on col=319 move to next row
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
        variable luma : unsigned(9 downto 0);  -- sum of shifts, max ~895
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
                        rd_state   <= RD_RRST;
                    end if;

                when RD_RRST =>
                    rrst_reg   <= '0';
                    byte_phase <= byte_phase + 1;
                    -- RCLK pulses during RRST (needed to clock the pointer reset)
                    if byte_phase < to_unsigned(4, 3) then
                        rclk_reg <= '1';
                    end if;
                    if byte_phase = to_unsigned(7, 3) then
                        byte_phase <= (others => '0');
                    end if;
                    if rrst_cnt /= 0 then
                        rrst_cnt <= rrst_cnt - 1;
                    else
                        rrst_reg  <= '1';
                        rd_state  <= RD_WAIT_FE;
                    end if;

                when RD_WAIT_FE =>
                    -- HREF just fell: the camera has finished writing this line
                    if href_fe = '1' then
                        byte_phase <= (others => '0');
                        byte_sel   <= '0';
                        byte0_reg  <= (others => '0');
                        col_cnt    <= (others => '0');
                        rd_state   <= RD_READ;
                    end if;
                    if vsy_fe = '1' then
                        row_cnt  <= (others => '0');
                        rd_state <= RD_IDLE;
                    end if;

                when RD_READ =>
                    byte_phase <= byte_phase + 1;

                    -- RCLK high for first half of byte cycle
                    if byte_phase < to_unsigned(4, 3) then
                        rclk_reg <= '1';
                    end if;

                    -- On phase 7 (end of byte cycle): latch cam_d
                    if byte_phase = to_unsigned(7, 3) then
                        byte_phase <= (others => '0');

                        if byte_sel = '0' then
                            -- First byte of RGB565 pair
                            byte0_reg <= cam_d;
                            byte_sel  <= '1';
                        else
                            -- Second byte: decode RGB565
                            -- byte0 = RRRRRGGG, cam_d = GGGBBBBB
                            r5 := unsigned(byte0_reg(7 downto 3));
                            g6 := unsigned(byte0_reg(2 downto 0)) & unsigned(cam_d(7 downto 5));
                            b5 := unsigned(cam_d(4 downto 0));
                            -- Expand to 8-bit (replicate MSBs into LSBs)
                            -- Expand to 8-bit: shift MSBs up, fill LSBs with MSBs
                            r8 := shift_left(resize(r5, 8), 3) or resize(r5(4 downto 2), 8);
                            g8 := shift_left(resize(g6, 8), 2) or resize(g6(5 downto 3), 8);
                            b8 := shift_left(resize(b5, 8), 3) or resize(b5(4 downto 2), 8);
                            -- BT.601 luma: Y = 0.299*R + 0.587*G + 0.114*B
                            -- Integer: Y = (R*77 + G*150 + B*29) >> 8
                            acc  := resize(r8 * to_unsigned(77,  8), 18)
                                  + resize(g8 * to_unsigned(150, 8), 18)
                                  + resize(b8 * to_unsigned(29,  8), 18);
                            gray := acc(15 downto 8);

                            -- Write to frame buffer
                            fb_wr_addr <= fb_wr_row * 320 + fb_wr_col;
                            fb_wr_data <= std_logic_vector(gray(7 downto 4));
                            fb_wr_en   <= '1';
                            dbg_byte   <= std_logic_vector(gray(7 downto 4));
                            byte_sel   <= '0';

                            if col_cnt = to_unsigned(319, 9) then
                                -- Line complete
                                if to_integer(row_cnt) < 239 then
                                    row_cnt <= row_cnt + 1;
                                end if;
                                rd_state <= RD_WAIT_FE;
                            else
                                col_cnt <= col_cnt + 1;
                            end if;
                        end if;
                    end if;

                    if vsy_fe = '1' then
                        row_cnt  <= (others => '0');
                        rd_state <= RD_IDLE;
                    end if;

            end case;

            -- Update write address helper signals
            fb_wr_row <= to_integer(row_cnt);
            fb_wr_col <= to_integer(col_cnt);

        end if;
    end process;

    -- -----------------------------------------------------------------------
    --  VGA pixel output: read frame buffer, output grayscale
    --  pix4 (4 bits) expanded to 8-bit by replication: pix8 = pix4 & pix4
    --  All three colour channels set equal -> grayscale
    -- -----------------------------------------------------------------------
    process(clk_100mhz)
        variable col  : integer range 0 to 319;
        variable row  : integer range 0 to 239;
        variable addr : integer range 0 to 76799;
        variable pix4 : std_logic_vector(3 downto 0);
        variable pix8 : std_logic_vector(7 downto 0);
    begin
        if rising_edge(clk_100mhz) then
            if pixel_tick = '1' then
                pix8 := (others => '0');
                if h_cnt < to_unsigned(H_ACTIVE, 10) and
                   v_cnt < to_unsigned(V_ACTIVE, 10) then
--                    col  := to_integer(h_cnt) / 2;
--                    row  := to_integer(v_cnt) / 2;
						  col  := to_integer(h_cnt) / 8;
                    row  := to_integer(v_cnt) / 8;
                    addr := row * 320 + col;
                    pix4 := framebuf(addr);
                    pix8 := pix4 & pix4;
                end if;
                vga_r <= pix8(7 downto 5);
                vga_g <= pix8(7 downto 5);
                vga_b <= pix8(7 downto 6);
            end if;
        end if;
    end process;

    -- -----------------------------------------------------------------------
    --  SCCB 100 kHz tick (1000 system clocks per tick)
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

    -- -----------------------------------------------------------------------
    --  SCCB FSM: writes all 12 registers in INIT_ROM
    --  After soft reset (first write), waits 500 ms before continuing
    -- -----------------------------------------------------------------------
    process(clk_100mhz)
    begin
        if rising_edge(clk_100mhz) then
            if tick_sccb = '1' then
                case sccb_state is
                    when S_WAIT =>
                        sioc_reg <= '1'; siod_out <= '1'; siod_oe <= '1';
                        if init_done = '1' then
                            rom_ptr <= 0; wr_cnt <= 0; bsel <= 0;
                            tx_byte <= INIT_ROM(0); bit_idx <= 7;
                            sccb_state <= S_START_A;
                        end if;

                    when S_START_A =>
                        sioc_reg <= '1'; siod_out <= '1'; siod_oe <= '1';
                        sccb_state <= S_START_B;

                    when S_START_B =>
                        sioc_reg <= '1'; siod_out <= '0'; siod_oe <= '1';
                        sccb_state <= S_BIT_LO;

                    when S_BIT_LO =>
                        sioc_reg <= '0';
                        siod_out <= tx_byte(bit_idx);
                        siod_oe  <= '1';
                        sccb_state <= S_BIT_HI;

                    when S_BIT_HI =>
                        sioc_reg <= '1';
                        if bit_idx = 0 then
                            sccb_state <= S_DC_LO;
                        else
                            bit_idx    <= bit_idx - 1;
                            sccb_state <= S_BIT_LO;
                        end if;

                    when S_DC_LO =>
                        sioc_reg <= '0'; siod_out <= '1'; siod_oe <= '0';
                        sccb_state <= S_DC_HI;

                    when S_DC_HI =>
                        sioc_reg <= '1'; siod_oe <= '1';
                        if bsel < 2 then
                            bsel    <= bsel + 1;
                            rom_ptr <= rom_ptr + 1;
                            tx_byte <= INIT_ROM(rom_ptr + 1);
                            bit_idx <= 7;
                            sccb_state <= S_BIT_LO;
                        else
                            sccb_state <= S_STOP_A;
                        end if;

                    when S_STOP_A =>
                        sioc_reg <= '0'; siod_out <= '0'; siod_oe <= '1';
                        sccb_state <= S_STOP_B;

                    when S_STOP_B =>
                        sioc_reg <= '1'; siod_out <= '1'; siod_oe <= '1';
                        -- Long gap after soft reset (wr_cnt=0), normal gap otherwise
                        if wr_cnt = 0 then
                            sccb_long <= '1';
                        else
                            sccb_long <= '0';
                        end if;
                        sccb_gap   <= (others => '0');
                        sccb_state <= S_GAP;

                    when S_GAP =>
                        -- Long gap = 500 ms = 50000 SCCB ticks
                        -- Short gap = 5 ms = 5000 SCCB ticks (to keep <100kHz)
                        -- Wait, sccb tick is 10us, so:
                        --   long: 50000 * 10us = 500ms
                        --   short: 500 * 10us = 5ms
                        if sccb_long = '1' then
                            if sccb_gap < to_unsigned(50000, 20) then
                                sccb_gap <= sccb_gap + 1;
                            else
                                sccb_gap   <= (others => '0');
                                sccb_long  <= '0';
                                rom_ptr    <= rom_ptr + 1;
                                if wr_cnt < NUM_WRITES - 1 then
                                    wr_cnt <= wr_cnt + 1;
                                    bsel   <= 0;
                                    tx_byte <= INIT_ROM(rom_ptr + 1);
                                    bit_idx <= 7;
                                    sccb_state <= S_START_A;
                                else
                                    sccb_done  <= '1';
                                    sccb_state <= S_DONE;
                                end if;
                            end if;
                        else
                            if sccb_gap < to_unsigned(500, 20) then
                                sccb_gap <= sccb_gap + 1;
                            else
                                sccb_gap <= (others => '0');
                                rom_ptr  <= rom_ptr + 1;
                                if wr_cnt < NUM_WRITES - 1 then
                                    wr_cnt <= wr_cnt + 1;
                                    bsel   <= 0;
                                    tx_byte <= INIT_ROM(rom_ptr + 1);
                                    bit_idx <= 7;
                                    sccb_state <= S_START_A;
                                else
                                    sccb_done  <= '1';
                                    sccb_state <= S_DONE;
                                end if;
                            end if;
                        end if;

                    when S_DONE =>
                        sioc_reg  <= '1'; siod_out <= '1'; siod_oe <= '1';
                        sccb_done <= '1';
                end case;
            end if;
        end if;
    end process;

end architecture;