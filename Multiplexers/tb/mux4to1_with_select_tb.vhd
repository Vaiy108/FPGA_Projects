--------------------------------------------------------------------------------
-- Company: 
-- Engineer:
--
-- Create Date:   22:44:57 02/18/2026
-- Design Name:   
--
-- 
-- VHDL Test Bench Created by ISE for module: With_Select_MUX4to1
-- 
-- Dependencies:
-- 
-- Revision:
-- Revision 0.01 - File Created
-- Additional Comments:
--
-- Notes: 
-- This testbench has been automatically generated using types std_logic and
-- std_logic_vector for the ports of the unit under test.  Xilinx recommends
-- that these types always be used for the top-level I/O of a design in order
-- to guarantee that the testbench will bind correctly to the post-implementation 
-- simulation model.
--------------------------------------------------------------------------------
LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
use IEEE.numeric_std.ALL;
 
-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
--USE ieee.numeric_std.ALL;
 
ENTITY With_Select_MUX4to1_tb IS
END With_Select_MUX4to1_tb;
 
ARCHITECTURE behavior OF With_Select_MUX4to1_tb IS 
 
    -- Component Declaration for the Unit Under Test (UUT)
 
    COMPONENT With_Select_MUX4to1
    PORT(
         w0 : IN  std_logic;
         w1 : IN  std_logic;
         w2 : IN std_logic;
         w3 : IN  std_logic;
          s :  IN unsigned(1 downto 0);
         En : IN  std_logic;
          f : OUT  std_logic
        );
    END COMPONENT;
    

   --Inputs
   signal w0 : std_logic := '0';
   signal w1 : std_logic := '0';
   signal w2 : std_logic := '0';
   signal w3 : std_logic := '0';
   signal s  : unsigned(1 downto 0) := (others => '0');
   signal En : std_logic := '0';

 	--Outputs
   signal f : std_logic;
   -- No clocks detected in port list. Replace <clock> below with 
   -- appropriate port name 
 
 
BEGIN
 
	-- Instantiate the Unit Under Test (UUT)
   uut: With_Select_MUX4to1 PORT MAP (
          w0 => w0,
          w1 => w1,
          w2 => w2,
          w3 => w3,
          s => s,
          En => En,
          f => f
        );
 

   -- Stimulus process
   stim_proc: process
   begin	
		w0 <= '0'; w1 <= '1'; w2 <= '0'; w3 <= '1';
		
		En <= '0';
		s  <= "00";
		
		wait for 20 ns;
		-- disabled sweep
		s <= "01"; wait for 20 ns;
		s <= "10"; wait for 20 ns;
		s <= "11"; wait for 20 ns;
		
		-- enabled sweep
		En <= '1';
		s <= "00"; wait for 20 ns;
		s <= "01"; wait for 20 ns;
		s <= "10"; wait for 20 ns;
		s <= "11"; wait for 20 ns;
      -- hold reset state for 100 ns.
   

      -- insert stimulus here 

      wait;
   end process;

END;
