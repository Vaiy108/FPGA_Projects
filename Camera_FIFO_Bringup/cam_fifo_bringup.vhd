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
        cam_siod   : out   std_logic;
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

    -- SCCB signals
    signal sccb_clk_div : unsigned(9 downto 0) := (others => '0');
    signal tick_sccb    : std_logic := '0';
    signal sioc_reg     : std_logic := '1';
    signal siod_reg     : std_logic := '1';

    type sccb_state_t is (
        WAIT_PWRUP,
        START_A, START_B,
        BIT_LOW, BIT_HIGH,
        ACK_LOW, ACK_HIGH,
        STOP_A, STOP_B,
        DONE
    );
    signal sccb_state   	: sccb_state_t := WAIT_PWRUP;

    signal byte_sel     	: integer range 0 to 5 := 0;
    signal bit_idx      	: integer range 0 to 7 := 7;
    signal tx_byte      	: std_logic_vector(7 downto 0) := x"42";
	 signal post_reset_wait : unsigned(19 downto 0) := (others => '0');
    signal init_done    	: std_logic := '0';

begin
    cam_rclk <= rclk_reg;
    cam_rrst <= rrst_reg;
    cam_oe   <= oe_reg;
    cam_sioc <= sioc_reg;
    cam_siod <= siod_reg;
    led      <= led_reg;

    --------------------------------------------------------------------------
    -- FIFO read / LED display 
    --------------------------------------------------------------------------
    process(clk_100mhz)
	 begin
		 if rising_edge(clk_100mhz) then
			  -- free-running divider
			  div_cnt <= div_cnt + 1;

			  -- Default LED sample clocking
			  sample_cnt <= sample_cnt + 1;

			  -- State 1: long startup wait
			  if startup_cnt < to_unsigned(5_000_000, startup_cnt'length) then
					startup_cnt <= startup_cnt + 1;

					-- FIFO outputs enabled (active low)
					oe_reg   <= '0';

					-- idle values before reset sequence
					rclk_reg <= '1';
					rrst_reg <= '1';

			  -- State 2: assert RRST low while RCLK high
			  elsif startup_cnt < to_unsigned(5_000_100, startup_cnt'length) then
					startup_cnt <= startup_cnt + 1;
					oe_reg   <= '0';
					rclk_reg <= '1';
					rrst_reg <= '0';

			  -- State 3: drive RCLK low
			  elsif startup_cnt < to_unsigned(5_000_200, startup_cnt'length) then
					startup_cnt <= startup_cnt + 1;
					oe_reg   <= '0';
					rclk_reg <= '0';
					rrst_reg <= '0';

			  -- State 4: drive RCLK high again (RRST sampled here)
			  elsif startup_cnt < to_unsigned(5_000_300, startup_cnt'length) then
					startup_cnt <= startup_cnt + 1;
					oe_reg   <= '0';
					rclk_reg <= '1';
					rrst_reg <= '0';

			  -- State 5: release RRST high
			  elsif startup_cnt < to_unsigned(5_000_400, startup_cnt'length) then
					startup_cnt <= startup_cnt + 1;
					oe_reg   <= '0';
					rclk_reg <= '0';
					rrst_reg <= '1';

			  -- State 6: normal readout
			  else
					oe_reg   <= '0';       -- active low = outputs enabled
					rrst_reg <= '1';       -- released
					rclk_reg <= div_cnt(7); -- slow read clock

					if sample_cnt = 0 then
						 led_reg <= cam_d;
					end if;
			  end if;
		 end if;
	 end process;

end architecture;
