
-- Engineer: Vasan Iyer 
--------ALU Implementation--------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;



entity ALU_module is
    Port ( 
				A 		: 		in  	signed 	(3 downto 0);
				B 		: 		in  	signed 	(3 downto 0);
				S 		: 		in  	unsigned (2 downto 0);
				F 		: 		out 	signed 	(3 downto 0)
			);
end ALU_module;


architecture Behavioral of ALU_module is

begin

	 F			<=		  (others=>'0') 	when	S = "000"	else
							B - A 			when	S = "001"	else
							A - B 			when	S = "010"	else
							A + B 			when	S = "011"	else
							A xor B 			when	S = "100"	else
							A or B			when	S = "101"	else
							A and B 			when	S = "110"	else
						  (others=>'1'); 	
							

end Behavioral;

