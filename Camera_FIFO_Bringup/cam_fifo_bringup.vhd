----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date:    20:55:33 04/12/2026 
-- Design Name: 
-- Module Name:    cam_fifo_bringup - Behavioral 
-- Project Name: 
-- Target Devices: 
-- Tool versions: 
-- Description: 
--
-- Dependencies: 
--
-- Revision: 
-- Revision 0.01 - File Created
-- Additional Comments: 
--
----------------------------------------------------------------------------------
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
		  cam_wrst 	 : out std_logic;
        led        : out   std_logic_vector(7 downto 0)
    );
end entity;

architecture rtl of cam_fifo_bringup is
    -- FIFO / LED test signals
    signal div_cnt      : unsigned(7 downto 0)  := (others => '0');
    signal rclk_reg     : std_logic := '0';
    signal startup_cnt  : unsigned(23 downto 0) := (others => '0');
    signal rrst_reg     : std_logic := '1';
    signal oe_reg       : std_logic := '0';
    signal sample_cnt   : unsigned(19 downto 0) := (others => '0');
    signal led_reg      : std_logic_vector(7 downto 0) := (others => '0');
	 
	 signal wrst_reg 		: std_logic := '1';
	 

    -- SCCB signals
    signal sccb_clk_div : unsigned(9 downto 0) := (others => '0');
    signal tick_sccb    : std_logic := '0';

    signal sioc_reg     : std_logic := '1';
    signal siod_out     : std_logic := '1';
    signal siod_oe      : std_logic := '1';
    signal siod_in      : std_logic;
	 
	 type sccb_state_t is (
        WAIT_PWRUP,
        START_A, START_B,
        BIT_LOW, BIT_HIGH,
        ACK_LOW, ACK_HIGH,
        STOP_A, STOP_B,
        DONE, FAIL
    );
    signal sccb_state   : sccb_state_t := WAIT_PWRUP;
	 
	 type reg_array_t is array (0 to 17) of std_logic_vector(7 downto 0);

	 constant init_rom : reg_array_t := (
		  x"42", x"12", x"80",  -- reset
		  x"42", x"11", x"01",  -- CLKRC
		  x"42", x"12", x"04",  -- COM7 RGB
		  x"42", x"8C", x"00",  -- RGB444 disable
		  x"42", x"40", x"D0",  -- COM15 full range + RGB565
		  x"42", x"3A", x"04"   -- TSLB
	 );
	 signal rom_idx          : integer range 0 to 17 := 0;
	 signal inter_write_wait : unsigned(19 downto 0) := (others => '0');
	 signal write_count      : integer range 0 to 5 := 0;
    signal byte_sel     	 : integer range 0 to 2 := 0;
    signal bit_idx      	 : integer range 0 to 7 := 7;
    signal tx_byte      	 : std_logic_vector(7 downto 0) := x"42";

    --signal ack_ok       : std_logic := '0';
    signal ack_seen     : std_logic_vector(2 downto 0) := (others => '0');
	 
begin
    cam_rclk <= rclk_reg;
    cam_rrst <= rrst_reg;
    cam_oe   <= oe_reg;
    cam_sioc <= sioc_reg;
	 cam_wrst <= wrst_reg;
	 -- LEDs for showing Camera data
    led      <= led_reg;
	 
	 -- SCCB debug LED assignments, using LEDs for SCCB
--	 led(0) <= ack_seen(0);
--	 led(1) <= ack_seen(1);
--	 led(2) <= ack_seen(2);
--	 led(3) <= '1' when sccb_state = DONE else '0';
--	 led(4) <= '1' when sccb_state = FAIL else '0';
--
--	 led(5) <= '1' when write_count >= 1 else '0';
--	 led(6) <= '1' when write_count >= 3 else '0';
--	 led(7) <= '1' when write_count = 5 else '0';
	 --led(7 downto 3) <= led_reg(7 downto 3);
------------------------------------------------------------
    -- Proper SCCB-style bidirectional data line:
    -- drive low/high when enabled, release to Z for ACK
    cam_siod <= '0' when (siod_oe = '1' and siod_out = '0') else 'Z';
    siod_in  <= cam_siod;

    --------------------------------------------------------------------------
    -- FIFO read / LED display
    --------------------------------------------------------------------------
    process(clk_100mhz)
    begin
        if rising_edge(clk_100mhz) then
            div_cnt <= div_cnt + 1;
            sample_cnt <= sample_cnt + 1;

            if startup_cnt < to_unsigned(5_000_000, startup_cnt'length) then
                startup_cnt <= startup_cnt + 1;
                oe_reg   <= '1';
                rrst_reg <= '1';
                rclk_reg <= '0';

            elsif startup_cnt < to_unsigned(5_000_100, startup_cnt'length) then
                startup_cnt <= startup_cnt + 1;
                oe_reg   <= '1';
                rrst_reg <= '0';
                rclk_reg <= '0';

            elsif startup_cnt < to_unsigned(5_000_200, startup_cnt'length) then
                startup_cnt <= startup_cnt + 1;
                oe_reg   <= '1';
                rrst_reg <= '0';
                rclk_reg <= '1';

            elsif startup_cnt < to_unsigned(5_000_300, startup_cnt'length) then
                startup_cnt <= startup_cnt + 1;
                oe_reg   <= '1';
                rrst_reg <= '1';
                rclk_reg <= '0';

            else
                oe_reg   <= '0';
                rrst_reg <= '1';
                rclk_reg <= div_cnt(7);

                if sample_cnt = 0 then
                    led_reg <= cam_d;
						  --led_reg <= (others => '0'); -- for Debug
                end if;
            end if;
        end if;
    end process;

    --------------------------------------------------------------------------
    -- SCCB tick generator
    --------------------------------------------------------------------------
    process(clk_100mhz)
    begin
        if rising_edge(clk_100mhz) then
            tick_sccb <= '0';
            sccb_clk_div <= sccb_clk_div + 1;
            if sccb_clk_div = 999 then
                sccb_clk_div <= (others => '0');
                tick_sccb <= '1';
            end if;
        end if;
    end process;

    --------------------------------------------------------------------------
    -- Proper single SCCB write with ACK check:
    -- 0x42, 0x12, 0x80
    --------------------------------------------------------------------------
    process(clk_100mhz)
    begin
        if rising_edge(clk_100mhz) then
            if tick_sccb = '1' then
                case sccb_state is
                    when WAIT_PWRUP =>
                        sioc_reg <= '1';
                        siod_out <= '1';
                        siod_oe  <= '1';
                        if startup_cnt > to_unsigned(2_000_000, startup_cnt'length) then
                            rom_idx     <= 0;
                            write_count <= 0;
								    byte_sel   <= 0;
                            tx_byte    <= init_rom(0);
                            bit_idx    <= 7;
									 ack_seen    <= (others => '0');
                            sccb_state <= START_A;
                        end if;

                    when START_A =>
                        sioc_reg <= '1';
                        siod_out <= '1';
                        siod_oe  <= '1';
                        sccb_state <= START_B;

                    when START_B =>
                        sioc_reg <= '1';
                        siod_out <= '0';
                        siod_oe  <= '1';
                        sccb_state <= BIT_LOW;

                    when BIT_LOW =>
                        sioc_reg <= '0';
                        siod_out <= tx_byte(bit_idx);
                        siod_oe  <= '1';
                        sccb_state <= BIT_HIGH;

                    when BIT_HIGH =>
                        sioc_reg <= '1';
                        if bit_idx = 0 then
                            sccb_state <= ACK_LOW;
                        else
                            bit_idx <= bit_idx - 1;
                            sccb_state <= BIT_LOW;
                        end if;

                    when ACK_LOW =>
                        sioc_reg <= '0';
                        siod_out <= '1';
                        siod_oe  <= '0';  -- release SIOD for camera ACK
                        sccb_state <= ACK_HIGH;

                    when ACK_HIGH =>
                        sioc_reg <= '1';
             
                        if siod_in = '0' then
                            ack_seen(byte_sel) <= '1';
                            siod_oe <= '1';

                            if byte_sel < 2 then
										  byte_sel <= byte_sel + 1;
                                rom_idx  <= rom_idx + 1;
                                tx_byte  <= init_rom(rom_idx + 1);
                                bit_idx    <= 7;
                                sccb_state <= BIT_LOW;
                            else
                                sccb_state <= STOP_A;
                            end if;
                        else
                            sccb_state <= FAIL;
                        end if;

                    when STOP_A =>
                        sioc_reg <= '0';
                        siod_out <= '0';
                        siod_oe  <= '1';
                        sccb_state <= STOP_B;

                    when STOP_B =>
                        sioc_reg <= '1';
                        siod_out <= '1';
                        siod_oe  <= '1';
                        
								if inter_write_wait < to_unsigned(50000, inter_write_wait'length) then
									 inter_write_wait <= inter_write_wait + 1;
									 sccb_state <= STOP_B;
							   else
									 inter_write_wait <= (others => '0');

									 if write_count < 5 then
										  write_count <= write_count + 1;
										  byte_sel    <= 0;
										  rom_idx     <= rom_idx + 1;
										  tx_byte     <= init_rom(rom_idx + 1);
										  bit_idx     <= 7;
										  ack_seen    <= (others => '0');
										  sccb_state  <= START_A;
									 else
										  sccb_state <= DONE;
									 end if;
							  end if;

                    when DONE =>
                        sioc_reg <= '1';
                        siod_out <= '1';
                        siod_oe  <= '1';
								sccb_state <= DONE;                        

                    when FAIL =>
                        sioc_reg <= '1';
                        siod_out <= '1';
                        siod_oe  <= '1';
                        sccb_state <= FAIL;
                end case;
            end if;
        end if;
    end process;
end architecture;
