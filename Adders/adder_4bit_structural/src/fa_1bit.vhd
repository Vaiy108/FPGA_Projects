----------------------------------------------------------------------------------
-- Company: 
-- Engineer:Vasan Iyer 

----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity Example_01_Full_Adder is
    Port ( 
			  A 			: in  	STD_LOGIC;
			  B 			: in  	STD_LOGIC;
			  C_In 		: in  	STD_LOGIC;
			  Sum 		: out  	STD_LOGIC;
			  C_Out 		: out  	STD_LOGIC
			 );
end Example_01_Full_Adder;

architecture Behavioral of example_01_Full_Adder is
--Concurrent section
begin

	sum  	<= A xor B xor C_In;
	
	C_Out	<= (A and B) or (A and C_In) or (B and C_In);	

end Behavioral;

