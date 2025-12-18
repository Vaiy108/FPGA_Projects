LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;
 
-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
--USE ieee.numeric_std.ALL;
 
ENTITY Example_01_FA_16bit_Signed_tb IS
END Example_01_FA_16bit_Signed_tb;
 
ARCHITECTURE behavior OF Example_01_FA_16bit_Signed_tb IS 
 
    -- Component Declaration for the Unit Under Test (UUT)
 
    COMPONENT Example_01_FA_16bit_Signed
    PORT(
				A 		: in  signed (15 downto 0);  -- 16 bit signal
				B 		: in  signed (15 downto 0); -- 16 bit signal
				Cin	: in	signed (0 downto 0); -- 1 bit signal
				Cout	: out	std_logic;
				Sum 	: out signed (15 downto 0)
        );
    END COMPONENT;
    

   --Inputs
   signal A 	: 	signed (15 downto 0) := (others => '0');
   signal B 	: 	signed (15 downto 0) := (others => '0');
   signal Cin 	: 	signed (0 downto 0) := (others => '0');

 	--Outputs
   signal Cout : std_logic;
   signal Sum 	: signed(15 downto 0);
   -- No clocks detected in port list. Replace <clock> below with 
   -- appropriate port name 
 

BEGIN
 
	-- Instantiate the Unit Under Test (UUT)
   uut: Example_01_FA_16bit_Signed PORT MAP (
          A => A,
          B => B,
          Cin => Cin,
          Cout => Cout,
          Sum => Sum
        );

 

   -- Stimulus process
   stim_proc: process
   begin		
    -- 1. Initialize and hold reset state
		 A    <= (others => '0'); 
		 B    <= (others => '0'); 
		 Cin <= "0";
		 wait for 100 ns;    

		 -- 2. Test Positive Addition (2 + 4 = 6)
		 A    <= x"0002"; -- 16-bit Hex for 2
		 B    <= x"0004"; -- 16-bit Hex for 4
		 Cin <= "0";
		 wait for 20 ns;
	
		 wait;
   end process;

END;
