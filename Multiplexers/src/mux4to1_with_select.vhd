library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.numeric_std.ALL;


entity With_Select_MUX4to1 is
	
	port
			(
				w0		:	in		std_logic;
				w1		:	in 	std_logic;
				w2		:	in		std_logic;
				w3		:	in 	std_logic;
				s		:	in		unsigned(1 downto 0);
				En		:	in		std_logic;
				f		:	out	std_logic
			);

end With_Select_MUX4to1;

architecture Behavioral of With_Select_MUX4to1 is

	signal	SEn		:	unsigned	(2 downto 0)	:=	(others=>'0');

begin
	
	SEn	<=	S & En;

	with SEn select
		f	<=	w0 when "001",
				w1 when "011",
				w2 when "101",
				w3 when "111",
				'0' when others;

end Behavioral;
