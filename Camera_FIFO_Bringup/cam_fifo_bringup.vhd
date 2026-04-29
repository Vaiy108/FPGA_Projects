
-- Architecture: read FIFO line-by-line triggered by HREF falling edge
-- RRST+WRST every VSYNC, double buffer 4-bit, 10MHz RCLK
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

    -- IOB register for cam_d: latch at pin for minimum path delay
    attribute IOB         : string;
    attribute IOB of cam_d : signal is "TRUE";

    constant H_ACTIVE : integer := 640;  constant H_FP   : integer := 16;
    constant H_SYNC   : integer := 96;   constant H_TOTAL : integer := 800;
    constant V_ACTIVE : integer := 480;  constant V_FP   : integer := 10;
    constant V_SYNC   : integer := 2;    constant V_TOTAL : integer := 525;
    constant CAM_ROWS : integer := 224;  constant CAM_COLS : integer := 160;

    signal clk_div    : unsigned(1 downto 0) := (others=>'0');
    signal pixel_tick : std_logic := '0';
    signal h_cnt      : unsigned(9 downto 0) := (others=>'0');
    signal v_cnt      : unsigned(9 downto 0) := (others=>'0');
    signal startup_cnt: unsigned(22 downto 0) := (others=>'0');
    signal init_done  : std_logic := '0';
    signal sccb_done  : std_logic := '0';
    signal oe_reg     : std_logic := '1';
    signal rrst_reg   : std_logic := '1';
    signal wrst_reg   : std_logic := '1';

    -- 7.14MHz RCLK (100MHz/14), registered output
    signal rclk_gen  : std_logic := '0';
    signal rclk_cnt  : unsigned(3 downto 0) := (others=>'0');
    signal rclk_en   : std_logic := '0';
    signal rclk_out  : std_logic := '0';

    signal href_meta : std_logic := '0'; signal href_sync : std_logic := '0';
    signal href_d    : std_logic := '0'; signal vsy_meta  : std_logic := '0';
    signal vsy_sync  : std_logic := '0'; signal vsy_d     : std_logic := '0';
    signal href_fe   : std_logic := '0'; signal vsy_fe    : std_logic := '0';

    -- Double framebuffer 4-bit: 2 x 160x224 = 16 BRAMs total
    type   framebuf_t  is array (0 to CAM_ROWS*CAM_COLS-1) of std_logic_vector(3 downto 0);
    signal framebuf_a  : framebuf_t;
    signal framebuf_b  : framebuf_t;
    attribute ram_style              : string;
    attribute ram_style of framebuf_a : signal is "block";
    attribute ram_style of framebuf_b : signal is "block";

    signal fb_wr_addr : unsigned(15 downto 0) := (others=>'0');
    signal fb_wr_en   : std_logic := '0';
    signal fb_wr_data : std_logic_vector(3 downto 0) := (others=>'0');
    signal vga_rd_addr: unsigned(15 downto 0) := (others=>'0');
    signal rd_data_a  : std_logic_vector(3 downto 0) := (others=>'0');
    signal rd_data_b  : std_logic_vector(3 downto 0) := (others=>'0');
    signal vga_rd_data: std_logic_vector(3 downto 0) := (others=>'0');
    signal vga_active : std_logic := '0';
    signal wr_buf     : std_logic := '0';
    signal frame_ok   : std_logic := '0';

    -- FSM
    type rd_t is (RD_IDLE, RD_RRST, RD_WAIT_FE, RD_READ, RD_WAIT_VSY);
    signal rd_state  : rd_t := RD_IDLE;
    signal rrst_cnt  : unsigned(4 downto 0) := (others=>'0');
    signal byte_sel  : std_logic := '0';
    signal col_cnt   : unsigned(8 downto 0) := (others=>'0');
    signal row_cnt   : unsigned(7 downto 0) := (others=>'0');
    signal cam_d_reg   : std_logic_vector(3 downto 0) := (others=>'0');
    signal cam_d_input : std_logic_vector(7 downto 0) := (others=>'0'); -- global snapshot

    -- SCCB
    signal sccb_div  : unsigned(10 downto 0) := (others=>'0');
    signal tick_sccb : std_logic := '0';
    signal sioc_reg  : std_logic := '1';
    signal siod_out  : std_logic := '1';
    signal siod_oe   : std_logic := '1';
    type sccb_t is (S_WAIT,S_START_A,S_START_B,S_BIT_LO,S_BIT_HI,
                    S_DC_LO,S_DC_HI,S_STOP_A,S_STOP_B,S_GAP,S_DONE);
    signal sccb_state : sccb_t := S_WAIT;

    type rom_t is array (0 to 80) of std_logic_vector(7 downto 0);
    constant INIT_ROM : rom_t := (
        x"42",x"12",x"80",  -- soft reset
        x"42",x"11",x"00",  -- CLKRC: no prescaler
        x"42",x"12",x"14",  -- COM7: QVGA+RGB (colour bar OFF)
        x"42",x"0C",x"04",  -- COM3: DCW enable
        x"42",x"3E",x"00",  -- COM14: no scaling
        x"42",x"70",x"3A",  -- SCALING_XSC
        x"42",x"71",x"35",  -- SCALING_YSC
        x"42",x"8C",x"00",  -- RGB444 off
        x"42",x"40",x"D0",  -- COM15: RGB565 full range
        x"42",x"3A",x"04",  -- TSLB
        x"42",x"15",x"02",  -- COM10: VSYNC active low
        x"42",x"17",x"16",  -- HSTART
        x"42",x"18",x"04",  -- HSTOP
        x"42",x"19",x"02",  -- VSTRT
        x"42",x"1A",x"7A",  -- VSTOP
        x"42",x"32",x"80",  -- HREF control
        x"42",x"03",x"0A",  -- VREF control
        x"42",x"13",x"E7",  -- COM8: AGC+AEC+AWB
        x"42",x"14",x"48",  -- COM9: gain ceiling
        x"42",x"3D",x"C0",  -- COM13: gamma+UV
        x"42",x"41",x"08",  -- COM16
        x"42",x"55",x"00",  -- brightness
        x"42",x"56",x"40",  -- contrast
        x"42",x"69",x"00",  -- GFIX
        x"42",x"74",x"00",  -- REG74
        x"42",x"B0",x"84",  -- denoise
        x"42",x"42",x"00"   -- COM17: colour bar OFF
    );
    constant NUM_WRITES : integer := 27;
    signal rom_ptr : integer range 0 to 83 := 0;
    signal wr_cnt  : integer range 0 to 27 := 0;
    signal bsel    : integer range 0 to 2  := 0;
    signal bit_idx : integer range 0 to 7  := 7;
    signal tx_byte : std_logic_vector(7 downto 0) := x"42";
    signal sccb_gap  : unsigned(15 downto 0) := (others=>'0');
    signal sccb_long : std_logic := '0';

begin
    cam_oe   <= oe_reg;
    cam_wrst <= wrst_reg;
    cam_rrst <= rrst_reg;
    cam_wr   <= '1';  -- WE inactive: FIFO write controlled by STR=HREF only
    cam_sioc <= sioc_reg;
    cam_siod <= '0' when (siod_oe='1' and siod_out='0') else 'Z';
    cam_rclk <= rclk_out;

    vga_hsync <= '0' when (h_cnt>=to_unsigned(H_ACTIVE+H_FP,10) and
                           h_cnt< to_unsigned(H_ACTIVE+H_FP+H_SYNC,10)) else '1';
    vga_vsync <= '0' when (v_cnt>=to_unsigned(V_ACTIVE+V_FP,10) and
                           v_cnt< to_unsigned(V_ACTIVE+V_FP+V_SYNC,10)) else '1';

    led(0)<=init_done; led(1)<=sccb_done; led(2)<=vsy_sync; led(3)<=href_sync;
    led(4)<='1' when rd_state=RD_READ     else '0';
    led(5)<=frame_ok;
    led(6)<='1' when rd_state=RD_WAIT_FE  else '0';
    led(7)<='1' when rd_state=RD_RRST or rd_state=RD_WAIT_VSY else '0';

    -- Pixel clock /4 = 25MHz
    process(clk_100mhz) begin
        if rising_edge(clk_100mhz) then
            pixel_tick<='0';
            if clk_div="11" then clk_div<=(others=>'0'); pixel_tick<='1';
            else clk_div<=clk_div+1; end if;
        end if;
    end process;

    -- VGA counters
    process(clk_100mhz) begin
        if rising_edge(clk_100mhz) then
            if pixel_tick='1' then
                if h_cnt=to_unsigned(H_TOTAL-1,10) then
                    h_cnt<=(others=>'0');
                    if v_cnt=to_unsigned(V_TOTAL-1,10) then v_cnt<=(others=>'0');
                    else v_cnt<=v_cnt+1; end if;
                else h_cnt<=h_cnt+1; end if;
            end if;
        end if;
    end process;

    -- Startup: hold OE high 40ms
    process(clk_100mhz) begin
        if rising_edge(clk_100mhz) then
            if startup_cnt(22)='0' then
                startup_cnt<=startup_cnt+1; oe_reg<='1'; init_done<='0';
            else oe_reg<='0'; init_done<='1'; end if;
        end if;
    end process;

    -- Camera sync (2FF synchroniser)
    process(clk_100mhz) begin
        if rising_edge(clk_100mhz) then
            href_meta<=cam_href; href_sync<=href_meta; href_d<=href_sync;
            vsy_meta <=cam_vsy;  vsy_sync <=vsy_meta;  vsy_d <=vsy_sync;
            href_fe  <=href_d and not href_sync;
            vsy_fe   <=vsy_d  and not vsy_sync;
        end if;
    end process;

    -- Global pipeline register: capture ALL 8 bits simultaneously
    -- at 100MHz clock edge before any logic touches them
    -- Eliminates skew from different wire lengths on Dupont cables
    process(clk_100mhz) begin
        if rising_edge(clk_100mhz) then
            cam_d_input <= cam_d;
        end if;
    end process;

    -- Free-running RCLK: 10MHz (100MHz/10), 50% duty cycle
    -- Camera writes at 12MHz, we read at 10MHz: always slightly behind, safe
    process(clk_100mhz) begin
        if rising_edge(clk_100mhz) then
            if rclk_cnt=to_unsigned(9,4) then
                rclk_cnt<=(others=>'0'); rclk_gen<='0';
            elsif rclk_cnt=to_unsigned(4,4) then
                rclk_cnt<=rclk_cnt+1; rclk_gen<='1';
            else
                rclk_cnt<=rclk_cnt+1;
            end if;
            rclk_out <= rclk_gen and rclk_en;
        end if;
    end process;

    -- Dual-port BRAMs
    process(clk_100mhz) begin
        if rising_edge(clk_100mhz) then
            if fb_wr_en='1' and wr_buf='0' then
                framebuf_a(to_integer(fb_wr_addr))<=fb_wr_data;
            end if;
            rd_data_a<=framebuf_a(to_integer(vga_rd_addr));
        end if;
    end process;
    process(clk_100mhz) begin
        if rising_edge(clk_100mhz) then
            if fb_wr_en='1' and wr_buf='1' then
                framebuf_b(to_integer(fb_wr_addr))<=fb_wr_data;
            end if;
            rd_data_b<=framebuf_b(to_integer(vga_rd_addr));
        end if;
    end process;
    vga_rd_data <= rd_data_b when wr_buf='0' else rd_data_a;

    -- FIFO read FSM
    process(clk_100mhz)
        variable fb_col  : unsigned(7 downto 0);
        variable addr    : unsigned(15 downto 0);
        variable rclk_fe : std_logic;
    begin
        if rising_edge(clk_100mhz) then
            rrst_reg<='1'; wrst_reg<='1'; fb_wr_en<='0';

            -- Sample at cnt=3: just before rising edge (cnt=4)
            -- Data stable for 50ns (5 clocks of low phase) after previous rising edge
            if rclk_cnt=to_unsigned(0,4) and rclk_gen='0' then
                rclk_fe:='1';
            else
                rclk_fe:='0';
            end if;

            -- Register cam_d at this point
            if rclk_fe='1' then
                cam_d_reg <= cam_d_input(7 downto 4);
            end if;

            case rd_state is

                when RD_IDLE =>
                    rclk_en<='0';
                    if sccb_done='1' and vsy_fe='1' then
                        rrst_reg<='0'; wrst_reg<='0';
                        rrst_cnt<=to_unsigned(16,5);
                        row_cnt<=(others=>'0'); col_cnt<=(others=>'0');
                        rd_state<=RD_RRST;
                    end if;

                when RD_RRST =>
                    rclk_en<='1'; rrst_reg<='0'; wrst_reg<='0';
                    if rclk_fe='1' then
                        if rrst_cnt/=0 then rrst_cnt<=rrst_cnt-1;
                        else rclk_en<='0'; rd_state<=RD_WAIT_FE;
                        end if;
                    end if;

                when RD_WAIT_FE =>
                    -- Force byte_sel=0 every line start regardless of history
                    byte_sel <= '0';
                    -- Disable RCLK only at end of byte cycle to prevent trailing pulse
                    if rclk_cnt = to_unsigned(9,4) then
                        rclk_en <= '0';
                    end if;
                    if href_fe='1' then
                        col_cnt<=(others=>'0');
                        rd_state<=RD_READ;
                    end if;

                when RD_READ =>
                    -- Only enable RCLK at start of byte cycle to avoid partial bytes
                    if rclk_cnt=to_unsigned(0,4) then
                        rclk_en<='1';
                    end if;
                    if rclk_fe='1' then
                        if byte_sel='0' then
                            -- cam_d_reg sampled at cnt=6: current byte, fully stable
                            if col_cnt(0)='0' then
                                fb_col:=col_cnt(8 downto 1);
                                addr:=resize(row_cnt & "0000000",16)
                                    + resize(row_cnt & "00000",  16)
                                    + resize(fb_col,             16);
                                fb_wr_addr<=addr;
                                fb_wr_data<=cam_d_reg;
                                fb_wr_en  <='1';
                            end if;
                            byte_sel<='1';
                        else
                            byte_sel<='0';
                            if col_cnt=to_unsigned(319,9) then
                                if row_cnt=to_unsigned(CAM_ROWS-1,8) then
                                    frame_ok<='1';
                                    rd_state<=RD_WAIT_VSY;
                                else
                                    row_cnt<=row_cnt+1;
                                    rd_state<=RD_WAIT_FE;
                                end if;
                                col_cnt<=(others=>'0');
                            else
                                col_cnt<=col_cnt+1;
                            end if;
                        end if;
                    end if;
                    -- rclk_en stays 1 until next state sets it to 0

                when RD_WAIT_VSY =>
                    byte_sel <= '0';
                    if rclk_cnt = to_unsigned(9,4) then
                        rclk_en <= '0';
                    end if;
                    if vsy_fe='1' then
                        wr_buf    <= not wr_buf;
                        rrst_reg  <='0'; wrst_reg<='0';
                        rrst_cnt  <=to_unsigned(16,5);
                        row_cnt   <=(others=>'0'); col_cnt<=(others=>'0');
                        rd_state  <=RD_RRST;
                    end if;

            end case;
        end if;
    end process;

    -- VGA output
    process(clk_100mhz)
        variable col     : unsigned(7 downto 0);
        variable row     : unsigned(7 downto 0);
        variable addr    : unsigned(15 downto 0);
        variable pix4    : std_logic_vector(3 downto 0);
        variable active_d: std_logic := '0';
    begin
        if rising_edge(clk_100mhz) then
            if pixel_tick='1' then
                if h_cnt<to_unsigned(H_ACTIVE,10) and
                   v_cnt<to_unsigned(V_ACTIVE,10) then
                    col :=h_cnt(9 downto 2);
                    row :=v_cnt(8 downto 1);
                    -- Clamp row to valid framebuffer range
                    if row >= to_unsigned(CAM_ROWS,8) then
                        row := to_unsigned(CAM_ROWS-1,8);
                    end if;
                    addr:=resize(row & "0000000",16)
                        + resize(row & "00000",  16)
                        + resize(col,            16);
                    vga_rd_addr<=addr; vga_active<='1';
                else
                    vga_rd_addr<=(others=>'0'); vga_active<='0';
                end if;
                pix4:=(others=>'0');
                if active_d='1' and frame_ok='1' then
                    pix4:=vga_rd_data;
                end if;
                -- Diagnostic: show row parity as top bit
                -- Remove after debugging
                -- pix4(3) := row(0);  -- uncomment to test
                vga_r<=pix4(3 downto 1);
                vga_g<=pix4(3 downto 1);
                vga_b<=pix4(3 downto 2);
                active_d:=vga_active;
            end if;
        end if;
    end process;

    -- SCCB tick 100kHz
    process(clk_100mhz) begin
        if rising_edge(clk_100mhz) then
            tick_sccb<='0';
            if sccb_div=to_unsigned(1999,11) then sccb_div<=(others=>'0'); tick_sccb<='1';
            else sccb_div<=sccb_div+1; end if;
        end if;
    end process;

    -- SCCB FSM
    process(clk_100mhz) begin
        if rising_edge(clk_100mhz) then
            if tick_sccb='1' then
                case sccb_state is
                    when S_WAIT => sioc_reg<='1'; siod_out<='1'; siod_oe<='1';
                        if init_done='1' then rom_ptr<=0; wr_cnt<=0; bsel<=0;
                            tx_byte<=INIT_ROM(0); bit_idx<=7; sccb_state<=S_START_A; end if;
                    when S_START_A => sioc_reg<='1'; siod_out<='1'; siod_oe<='1'; sccb_state<=S_START_B;
                    when S_START_B => sioc_reg<='1'; siod_out<='0'; siod_oe<='1'; sccb_state<=S_BIT_LO;
                    when S_BIT_LO  => sioc_reg<='0'; siod_out<=tx_byte(bit_idx); siod_oe<='1'; sccb_state<=S_BIT_HI;
                    when S_BIT_HI  => sioc_reg<='1';
                        if bit_idx=0 then sccb_state<=S_DC_LO;
                        else bit_idx<=bit_idx-1; sccb_state<=S_BIT_LO; end if;
                    when S_DC_LO => sioc_reg<='0'; siod_out<='1'; siod_oe<='0'; sccb_state<=S_DC_HI;
                    when S_DC_HI => sioc_reg<='1'; siod_oe<='1';
                        if bsel<2 then bsel<=bsel+1; rom_ptr<=rom_ptr+1;
                            tx_byte<=INIT_ROM(rom_ptr+1); bit_idx<=7; sccb_state<=S_BIT_LO;
                        else sccb_state<=S_STOP_A; end if;
                    when S_STOP_A => sioc_reg<='0'; siod_out<='0'; siod_oe<='1'; sccb_state<=S_STOP_B;
                    when S_STOP_B => sioc_reg<='1'; siod_out<='1'; siod_oe<='1';
                        if wr_cnt=0 then sccb_long<='1'; else sccb_long<='0'; end if;
                        sccb_gap<=(others=>'0'); sccb_state<=S_GAP;
                    when S_GAP =>
                        if sccb_long='1' then
                            if sccb_gap<to_unsigned(50000,16) then sccb_gap<=sccb_gap+1;
                            else sccb_gap<=(others=>'0'); sccb_long<='0'; rom_ptr<=rom_ptr+1;
                                if wr_cnt<NUM_WRITES-1 then wr_cnt<=wr_cnt+1; bsel<=0;
                                    tx_byte<=INIT_ROM(rom_ptr+1); bit_idx<=7; sccb_state<=S_START_A;
                                else sccb_done<='1'; sccb_state<=S_DONE; end if; end if;
                        else
                            if sccb_gap<to_unsigned(500,16) then sccb_gap<=sccb_gap+1;
                            else sccb_gap<=(others=>'0'); rom_ptr<=rom_ptr+1;
                                if wr_cnt<NUM_WRITES-1 then wr_cnt<=wr_cnt+1; bsel<=0;
                                    tx_byte<=INIT_ROM(rom_ptr+1); bit_idx<=7; sccb_state<=S_START_A;
                                else sccb_done<='1'; sccb_state<=S_DONE; end if; end if;
                        end if;
                    when S_DONE => sioc_reg<='1'; siod_out<='1'; siod_oe<='1'; sccb_done<='1';
                end case;
            end if;
        end if;
    end process;

end architecture;