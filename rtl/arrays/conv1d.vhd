-------------------------------------------------------------------------------------------------
-- CONVOLUTION   -  out/20120 - MORAES
-------------------------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_signed.all;
use IEEE.std_logic_arith.all;

entity conv1d is
     generic (  X_SIZE : integer := 32 ;  
                FILTER_WIDTH : integer := 3 ;
                CONVS_PER_LINE  : integer := 15 ;
                MEM_SIZE  : integer := 10 ;
                INPUT_SIZE  : integer := 8 ;
                CARRY_SIZE : integer := 4
             );
     port    (  clock, reset   : in  std_logic;
                address_out    : out  unsigned(MEM_SIZE-1 downto 0);   -- feature map address
                data_from_mem  : in  std_logic_vector(INPUT_SIZE-1 downto 0);    -- value from feature map memory
                start_line     : in std_logic;
                weight_en      : in std_logic;
                bias_en        : in std_logic;
                valid          : out std_logic;                       -- valid data
                pixel          : out std_logic_vector(((INPUT_SIZE*2)+CARRY_SIZE)-1 downto 0)    -- result
             );
end entity conv1d;


architecture a1 of conv1d is

    type states is (ENDIDLE, END0, END1, END2);
    signal EA_add, PE_add : states;

    signal addressX, x, y, weight_x, bias_x: unsigned(MEM_SIZE-1 downto 0);

    ---- fixed weights ----------------------------------------------------------     
    type wgh3x3 is array (0 to 2, 0 to 2) of std_logic_vector(INPUT_SIZE-1 downto 0);
    signal weight : wgh3x3;
    
    type feature_column is array (0 to 2) of std_logic_vector(INPUT_SIZE-1 downto 0);  
    signal features    : feature_column;
    signal weight_mux : feature_column;
    
    -- signals for the convolution 
    type array_column is array (0 to 2) of std_logic_vector(((INPUT_SIZE*2)+CARRY_SIZE)-1 downto 0);  -- 20 bits
    signal op1, op2, res_mac, reg_mac : array_column;

    type control is array (0 to 2) of std_logic; 
    signal end_mac : control;

    signal soma  : std_logic_vector(((INPUT_SIZE*2)+CARRY_SIZE)-1 downto 0);
    signal ofmap : std_logic_vector(((INPUT_SIZE*2)+CARRY_SIZE)-1 downto 0);
    signal reg_bias_value : std_logic_vector(INPUT_SIZE-1 downto 0);
 
    signal fim_op, endRead_and_startMac, d1, d2, internal_reset, reset_reg: std_logic;

    signal count_acc, count_eop, cont_mac_cycle : std_logic_vector(4 downto 0);
    signal count_column, count_convolutions : unsigned(MEM_SIZE-1 downto 0);
    
    signal reg_weight_en : std_logic;
    
begin

   ----------------------------------------------------------------------------
   -- manages weights
   ----------------------------------------------------------------------------
   process(reset, clock)
   begin
      if reset='1' then
         weight_x       <= (others => '0');
         weight         <= (others=>(others =>(others =>'0')));
      elsif rising_edge(clock) then
         if (reg_weight_en = '1') then
               
            weight_x <= weight_x + 1;
            
            if (weight_x = 0) then
               weight(0,0) <= data_from_mem;
                              
            elsif (weight_x = 1) then
               weight(0,1) <= data_from_mem;
                              
            elsif (weight_x = 2) then
               weight(0,2) <= data_from_mem;
                             
            elsif (weight_x = 3) then
               weight(1,0) <= data_from_mem;
                              
            elsif (weight_x = 4) then
               weight(1,1) <= data_from_mem;
                             
            elsif (weight_x = 5) then
               weight(1,2) <= data_from_mem;
                              
            elsif (weight_x = 6) then
               weight(2,0) <= data_from_mem;
                              
            elsif (weight_x = 7) then
               weight(2,1) <= data_from_mem;
                              
            elsif (weight_x = 8) then
               weight(2,2) <= data_from_mem;
                              
            end if;
         else
            weight_x <= (others => '0');
         end if;
      end if;
   end process;
    
    ----------------------------------------------------------------------------
    -- manages the x and y addresses
    ----------------------------------------------------------------------------
    process(reset, clock)
    begin
          if reset='1' then
              x <= (others => '0');
              y <= (others => '0');
          elsif rising_edge(clock) then             
             if EA_add = END2 then
                if x < X_SIZE - 1 then
                  if (count_column < 2) then
                     x <= x+1;
                  end if;
                else
                   x <= (others => '0');   -- start of a new line
                   y <= y + 2*X_SIZE;
                end if;
            end if;
          end if;
    end process;


    ----------------------------------------------------------------------------
    -- state machine to manage the feature map access
    -- the idea is to make 6 readings - assuming stride=2
    ----------------------------------------------------------------------------
    process(reset, clock)
    begin
          if reset='1' then
             EA_add <= ENDIDLE;
             count_column <= (others=>'0');
             count_convolutions <= (others=>'0');
          elsif rising_edge(clock) then
             EA_add <= PE_add;
             
             -- column control
             if (EA_add = ENDIDLE and fim_op = '1') then
               count_column <= count_column + 1;
               if (count_column = 2) then
                  count_convolutions <= count_convolutions + 1;
                  count_column <= (others=>'0');
               end if;
             end if;
             
          end if;
    end process;

    process (reset, clock)
    begin
            internal_reset <= '0';
            
            case EA_add is
                when ENDIDLE =>  -- advance with an external command or when the computation finishes
                                 if start_line='1' or fim_op='1' then
                                       PE_add <= END0;
                                 else 
                                        PE_add <= ENDIDLE; 
                                 end if;
                                 addressX <= x;

                when END0    =>  PE_add <= END1;
                                 addressX <= x;       --------------------------- addresses to access memory

                when END1    =>  PE_add <= END2;
                                 addressX <= x + X_SIZE;
                                 
                when END2    =>  PE_add <= ENDIDLE;
                                 addressX <= x + 2*X_SIZE;
                                 
                                 -- internal reset to control accumulation
                                 if (unsigned(count_convolutions) > 0 and count_column = 0) then
                                    internal_reset <= '1';
                                 end if;
            end case;               
    end process;

    address_out <= bias_x   when bias_en = '1' else 
                   weight_x when weight_en = '1' else 
                   addressX+y;

    -- read from memory filling the features matriz (buffer)
    process(reset, clock)
    begin
          if reset='1' then
             features <= (others =>(others =>'0'));
             endRead_and_startMac <= '0';
          elsif rising_edge(clock) then
	    
	    endRead_and_startMac <= '0';
	    
            case EA_add is

               when END0  => features(0) <= data_from_mem;
                              
               when END1  => features(1) <= data_from_mem;

               when END2  => features(2) <= data_from_mem;
                             endRead_and_startMac <= '1';

               when others => endRead_and_startMac <= '0';
            end case;

        end if;
    end process;
  
   -------------------------------------------------------------------------------------------------- 
   --- weight manager
   ------------------------------------------------------------------------------------------------- 
   
   weight_mux(0) <= weight(0,0) when count_column = 0 else
                    weight(0,1) when count_column = 1 else
                    weight(0,2);
   
   weight_mux(1) <= weight(1,0) when count_column = 0 else
                    weight(1,1) when count_column = 1 else
                    weight(1,2);
                     
   weight_mux(2) <= weight(2,0) when count_column = 0 else
                    weight(2,1) when count_column = 1 else
                    weight(2,2);
                        
   ----------------------------------------------------------------------------------- 
   --- convolution end control
   -------------------------------------------------------------------------------------------------

   process(clock,reset)
   begin
      if (reset = '1') then
         count_eop <= (others=>'0');
      elsif rising_edge(clock) then
         if (fim_op = '1') then
            count_eop <= count_eop + '1';
         elsif (count_eop = 3) then
            count_eop <= (others=>'0');
         end if;
      end if;
   end process;
   
   -------------------------------------------------------------------------------------------------- 
   --- macs and flops array
   -------------------------------------------------------------------------------------------------

   -- the first column does not hava a previous sum
   cols0:  for j in 0  to 2 generate
              mac0: entity work.mac
                  generic map( INPUT_SIZE  => INPUT_SIZE, 
                               CARRY_SIZE => CARRY_SIZE
                  )
                  port map( sum      => reg_mac(j), 
                            op1      => weight_mux(j),  -- caution to read the weihts
                            op2      => features(j),
                            res_mac  => res_mac(j)
                          );
   end generate cols0; 

   reset_reg <= internal_reset or reset;
   
   reg_c:  for j in 0  to 2 generate
      ireg: entity work.reg
         generic map( INPUT_SIZE  => ((INPUT_SIZE*2)+CARRY_SIZE) )  
         port map( clock=>clock, reset=>reset_reg, enable=>fim_op,
                   D  => res_mac(j), 
                   Q  => reg_mac(j) 
                 );
   end generate reg_c;  
   
   -- process to control the number of cycles spend by the MACs
   process(clock,reset)
   begin
      if (reset = '1') then
	cont_mac_cycle <= (others=>'0');
	fim_op <= '0';
      elsif rising_edge(clock) then
	fim_op <= '0';
	if endRead_and_startMac = '1' or cont_mac_cycle > 0 then
	  cont_mac_cycle <= cont_mac_cycle + 1;
	  if cont_mac_cycle = 4 then
	    cont_mac_cycle <= (others=>'0');
	    fim_op <= '1';
	  end if;
	end if;
      end if;
   end process;

   -- compute the result (it may be valid or invalid)
   soma  <=  reg_mac(0) +  reg_mac(1) +  reg_mac(2) + reg_bias_value;
   
   -- ReLU operation
   ofmap(((INPUT_SIZE*2)+CARRY_SIZE)-1 downto ((INPUT_SIZE*2)+CARRY_SIZE)-4) <= (others=>'0');
   ofmap(((INPUT_SIZE*2)+CARRY_SIZE)-5 downto 0) <= soma(((INPUT_SIZE*2)+CARRY_SIZE)-1 downto 4) when soma > 0 else
                                                    (others=>'0');
   
    ----------------------------------------------------------------------------
    -- registering inputs and bias control
    ----------------------------------------------------------------------------
     process(reset, clock)
     begin
          if reset='1' then
             reg_weight_en <= '0';
             bias_x <= (others=>'0');
             reg_bias_value <= (others=>'0');
          elsif rising_edge(clock) then
             reg_weight_en  <= weight_en;
                      
             if (bias_en = '1') then
               reg_bias_value <= data_from_mem;
               bias_x <= bias_x + '1';
             end if;
             
          end if;
    end process;
    
    ----------------------------------------------------------------------------
    -- two clock cycles to store the result and count the executed convolutions
    ----------------------------------------------------------------------------
    process(reset, clock)
    begin
          if reset='1' then
             d1 <= '0';
             d2 <= '0';
             valid <= '0';
             count_acc <= (others=>'0');
             pixel <= (others=>'0');
          elsif rising_edge(clock) then
             d1 <= fim_op;
             d2 <= d1;                
             
             if count_eop = FILTER_WIDTH and count_acc > 0 then
                  valid <= d1;       
                  pixel <= ofmap;
             else
                  valid <= '0';
             end if;

             if fim_op='1'  then
                 if count_acc = CONVS_PER_LINE then
                      count_acc <= (others=>'0'); 
                 else
                     count_acc <= count_acc+1;
                 end if;
             end if;

          end if;
    end process;
 
end a1;
