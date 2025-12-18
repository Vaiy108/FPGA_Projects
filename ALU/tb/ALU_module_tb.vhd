
-- Engineer: Vasan Iyer
--
-- Create Date:   19:52:17 12/18/2025
-- Design Name:   
-- Module Name:   C:/Projects/ALU_Module/ALU_module_tb.vhd
-- Project Name:  ALU_Module
-- Target Device:  
-- Tool versions:  
-- Description:   
-- 
-- VHDL Test Bench Created by ISE for module: ALU_module
--------------------------------------------------------------------------------
LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;
 
 
ENTITY ALU_module_tb IS
END ALU_module_tb;
 
ARCHITECTURE behavior OF ALU_module_tb IS 
 
    -- Component Declaration for the Unit Under Test (UUT)
 
    COMPONENT ALU_module
    PORT(
         A : IN   signed(3 downto 0);
         B : IN   signed(3 downto 0);
         S : IN   unsigned(2 downto 0);
         F : OUT  signed(3 downto 0)
        );
    END COMPONENT;
    

   --Inputs
   signal A : signed(3 downto 0) := (others => '0');
   signal B : signed(3 downto 0) := (others => '0');
   signal S : unsigned(2 downto 0) := (others => '0');

 	--Outputs
   signal F : signed(3 downto 0);
   -- No clocks detected in port list. Replace <clock> below with 
   -- appropriate port name 
 
 
BEGIN
 
	-- Instantiate the Unit Under Test (UUT)
   uut: ALU_module PORT MAP (
          A => A,
          B => B,
          S => S,
          F => F
        );

   -- Stimulus process
   stim_proc: process
   begin		
      -- hold reset state for 100 ns.
      wait for 100 ns;	

      -- insert stimulus here
			A	<=	"0010";
			B	<=	"0010";
			S	<=	"110";

      wait for 100 ns;
			S	<=	"010";
			
		wait;
   end process;

END;
