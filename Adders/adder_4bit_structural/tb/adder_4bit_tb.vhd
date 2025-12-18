
--------------------------------------------------------------------------------
LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
 
-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
--USE ieee.numeric_std.ALL;
 
ENTITY Example_02_FA_4bit_tb IS
END Example_02_FA_4bit_tb;
 
ARCHITECTURE behavior OF Example_02_FA_4bit_tb IS 
 
    -- Component Declaration for the Unit Under Test (UUT)
 
    COMPONENT Example_02_FA_4bit
    PORT(
         A : IN  std_logic_vector(3 downto 0);
         B : IN  std_logic_vector(3 downto 0);
         C_In : IN  std_logic;
         Sum : OUT  std_logic_vector(3 downto 0);
         C_Out : OUT  std_logic
        );
    END COMPONENT;
    

   --Inputs
   signal A : std_logic_vector(3 downto 0) := (others => '0');
   signal B : std_logic_vector(3 downto 0) := (others => '0');
   signal C_In : std_logic := '0';

 	--Outputs
   signal Sum : std_logic_vector(3 downto 0);
   signal C_Out : std_logic;
   -- No clocks detected in port list. Replace <clock> below with 
   -- appropriate port name 
 
--   constant <clock>_period : time := 10 ns;
 
BEGIN
 
	-- Instantiate the Unit Under Test (UUT)
   uut: Example_02_FA_4bit PORT MAP (
          A => A,
          B => B,
          C_In => C_In,
          Sum => Sum,
          C_Out => C_Out
        );


   -- Stimulus process
   stim_proc: process
   begin		
      -- hold reset state for 100 ns.
      wait for 100 ns;	


      -- insert stimulus here
		A		<= "0010";
		B		<=	"0100";
		C_In	<= '1';		

      wait;
   end process;

END;
