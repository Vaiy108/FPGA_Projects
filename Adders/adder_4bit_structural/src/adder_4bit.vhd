
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity Example_02_FA_4bit is
    Port ( 
				  A 			: in  		STD_LOGIC_VECTOR (3 downto 0);
				  B 			: in  		STD_LOGIC_VECTOR (3 downto 0);
				  C_In 		: in  		STD_LOGIC;
				  Sum 		: out  		STD_LOGIC_VECTOR (3 downto 0);
				  C_Out 		: out  		STD_LOGIC
			  );
end Example_02_FA_4bit;

architecture Behavioral of Example_02_FA_4bit is
--Declarative region--

COMPONENT Example_01_Full_Adder
	PORT(
				A : IN std_logic;
				B : IN std_logic;
				C_In : IN std_logic;          
				Sum : OUT std_logic;
				C_Out : OUT std_logic
		   );
	END COMPONENT;
	
	signal	C_Int		:	std_logic_vector(2 downto 0)		:= "000";

begin
--Instantiation region-- Add  labels such as FA_0 to indicate the modules

	FA_0: Example_01_Full_Adder PORT MAP(
			A 			=> A(0),
			B 			=> B(0),
			C_In 		=> C_In,
			Sum 		=> Sum(0),
			C_Out 	=> C_Int(0)
		);
		
	FA_1: Example_01_Full_Adder PORT MAP(
			A 			=> A(1),
			B 			=> B(1),
			C_In 		=> C_Int(0),
			Sum 		=> Sum(1),
			C_Out 	=> C_Int(1)
		);
		
	FA_2: Example_01_Full_Adder PORT MAP(
			A 			=> A(2),
			B 			=> B(2),
			C_In 		=> C_Int(1),
			Sum 		=> Sum(2),
			C_Out 	=> C_Int(2)
		);
		
	FA_3: Example_01_Full_Adder PORT MAP(
			A 			=> A(3),
			B 			=> B(3),
			C_In 		=> C_Int(2),
			Sum 		=> Sum(3),
			C_Out 	=> C_Out
		);

end Behavioral;

