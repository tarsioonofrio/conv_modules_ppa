-------------------------------------------------------------------------------------------------
-- systolic2d - SYSTOLIC   -  JAN/2021 - MORAES  -  you must read the weights - fixed here 
-- MODIFIED IN MARCH 8 2021 - COMBINATIONAL MAC
-------------------------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_signed.all;
use IEEE.std_logic_arith.CONV_STD_LOGIC_VECTOR;

entity systolic2d is
  generic (
    X_SIZE         : integer := 32;
    FILTER_WIDTH   : integer := 3;
    CONVS_PER_LINE : integer := 15;
    MEM_SIZE       : integer := 10;
    INPUT_SIZE     : integer := 8;
    CARRY_SIZE     : integer := 4
    );
  port (
    clock         : in  std_logic;
    reset         : in  std_logic;
    address_out   : out std_logic_vector(9 downto 0);  -- feature map address
    data_from_mem : in  std_logic_vector(7 downto 0);  -- value from feature map memory
    start_line    : in  std_logic;
    weight_en     : in  std_logic;
    bias_en       : in  std_logic;
    valid         : out std_logic;      -- valid data
    pixel         : out std_logic_vector(19 downto 0)  -- result
    );
end entity systolic2d;


architecture a1 of systolic2d is

  --type statesM is (RIDLE, UPDATEADD, E0, E1, E2, E3, E4, E5);
  type statesM is (RIDLE, UPDATEADD, E0, E1, E2);
  signal EA_add, PE_add : statesM;

  signal en_reg, pipe_reset, change_line: std_logic;

  ---- fixed weights ----
  type wgh3x3 is array (0 to 2, 0 to 2) of std_logic_vector(7 downto 0);
  signal weight : wgh3x3;

  type features_3x3 is array (0 to 2, 0 to 2) of std_logic_vector(7 downto 0);
  signal features: features_3x3;

  type features_3 is array (0 to 2) of std_logic_vector(7 downto 0);
  signal buffer_features : features_3;


  -- signals for the systolic2d 
  type array3x3 is array (0 to 2, 0 to 2) of std_logic_vector(19 downto 0);  -- 20 bits
  signal op1, op2, res_mac, reg_mac : array3x3;

  signal reg_soma1, reg_soma2, reg_soma3 : std_logic_vector(19 downto 0);

  type address is array (0 to 5) of std_logic_vector(9 downto 0);
  signal add : address;
  signal pad : std_logic_vector(2 downto 0);

  signal cont_steps : std_logic_vector(4 downto 0);

  signal H : integer range -1 to X_SIZE + 1;
  signal V : integer range -X_SIZE to X_SIZE + 1024;  --------------------------------------- melhorar

  --signal change_line : integer range 0 to 2;  --------------------------------------- melhorar

  -- signals for bias and weights control
  signal weight_x, bias_x : std_logic_vector(9 downto 0);
  signal reg_bias_value   : std_logic_vector(7 downto 0);
  signal reg_weight_en    : std_logic;

  -- signal for shift + ReLU
  signal shift_output : std_logic_vector(19 downto 0);

  -- signals to synchronize valid 
  signal cont_iterations : std_logic_vector(9 downto 0);


begin
  ----------------------------------------------------------------------------
  -- menage bias
  ----------------------------------------------------------------------------
  process(reset, clock)
  begin
    if reset = '1' then
      bias_x         <= (others => '0');
      reg_bias_value <= (others => '0');
    elsif rising_edge(clock) then
      if (bias_en = '1') then
        reg_bias_value <= data_from_mem;
        bias_x         <= bias_x + '1';
      end if;
    end if;
  end process;

  ----------------------------------------------------------------------------
  -- manage weights
  ----------------------------------------------------------------------------
  process(reset, clock)
  begin
    if reset = '1' then
      reg_weight_en <= '0';
      weight_x      <= (others => '0');
      weight        <= (others => (others => (others => '0')));
    elsif rising_edge(clock) then
      -- register weight_en signal to ensure the correct weight value read
      reg_weight_en <= weight_en;

      if (reg_weight_en = '1') then

        weight_x <= weight_x + 1;

        if (weight_x = 0) then
          weight(0, 0) <= data_from_mem;

        elsif (weight_x = 1) then
          weight(0, 1) <= data_from_mem;

        elsif (weight_x = 2) then
          weight(0, 2) <= data_from_mem;

        elsif (weight_x = 3) then
          weight(1, 0) <= data_from_mem;

        elsif (weight_x = 4) then
          weight(1, 1) <= data_from_mem;

        elsif (weight_x = 5) then
          weight(1, 2) <= data_from_mem;

        elsif (weight_x = 6) then
          weight(2, 0) <= data_from_mem;

        elsif (weight_x = 7) then
          weight(2, 1) <= data_from_mem;

        elsif (weight_x = 8) then
          weight(2, 2) <= data_from_mem;

        end if;
      else
        weight_x <= (others => '0');
      end if;
    end if;
  end process;


  -------------------------------------------------------------------------------------------------------
  -- PART 1 - CONTROL: READS SIX ELEMENTS FROM MEMORY COMPUTING IN PARALLEL
  -------------------------------------------------------------------------------------------------------
  process(reset, clock)
  begin
    if reset = '1' then
      EA_add <= RIDLE;
    elsif rising_edge(clock) then
      EA_add <= PE_add;
    end if;
  end process;

  process (EA_add, start_line, weight_en)
  begin
    case EA_add is
      when RIDLE =>
        if (start_line = '1' and weight_en = '0') then
          PE_add <= UPDATEADD;
        else
          PE_add <= RIDLE;
        end if;

      when UPDATEADD => PE_add <= E0;  -- read 6 values from the memory **** continously ****
      when E0        => PE_add <= E1;
      when E1        => PE_add <= E2;
      when E2        => PE_add <= UPDATEADD;
    end case;
  end process;

  --  memory read address:  based on the address obtained from the reading state machine - two first columns

  address_out <= bias_x when bias_en = '1' else
                 weight_x when weight_en = '1' else
                 add(0)   when EA_add = E0 and pad(0) = '0' else
                 add(1)   when EA_add = E1 and pad(1) = '0' else
                 add(2)   when EA_add = E1 and pad(2) = '0' else
                 (others => '0');

  -- read from memory filling the features matriz, the first cycle update the addresses
  process(reset, clock)
  begin
    if reset = '1' then
      H               <= -1;
      V               <= -X_SIZE;
      add             <= (others => (others => '0'));
      buffer_features <= (others => (others => '0'));
      features        <= (others => (others => (others => '0')));
      cont_steps      <= (others => '0');
      pad             <= (others => '1');

    elsif rising_edge(clock) then
      case EA_add is

        when UPDATEADD =>
          --
          -- UPDATE THE ADDRESS IN A PIPELINE FASHION (only 2 colums)
          --
          add(0) <= CONV_STD_LOGIC_VECTOR(V + H, 10);
          add(1) <= X_SIZE + add(0);
          add(2) <= X_SIZE + add(1);

          --
          -- NEXT LINE
          --  
          if H = -1 then
            H <= H+1;
            V <= V+X_SIZE;
            pad(0) <= '1';
          elsif (H+1) >= X_SIZE + 1 then
            H <=-1;
            V <= V+X_SIZE;
            pad(0) <= '1';
          else
            H <= H+1;
            pad(0) <= '0';
          end if;

          pad(1) <= pad(0);
          pad(2) <= pad(1);


          --
          -- TRANSFER THE READ DATA, REUSING THE FIRST COLUM TO THE THIRD ONE
          --
          features(0, 0) <= buffer_features(0);
          features(0, 1) <= buffer_features(0);
          features(0, 2) <= buffer_features(0);

          features(1, 0) <= buffer_features(1);
          features(1, 1) <= buffer_features(1);
          features(1, 2) <= buffer_features(1);


          features(2, 0) <= buffer_features(2);
          features(2, 1) <= buffer_features(2);
          features(2, 2) <= buffer_features(2);

          -- count the number os arithmetic shifts
          if cont_steps < 7 then  -- stop at 7 - enough to fire accumulation
            cont_steps <= cont_steps + 1;
          end if;
        when E0 => 
          if pad(0) = '0' then
            buffer_features(0) <= data_from_mem;  --------- COMPUTE WITH PREVIOUS DATA
          else
            buffer_features(0) <= (others => '0');
          end if;
        when E1 =>
          if pad(1) = '0' then
            buffer_features(1) <= data_from_mem;  --------- COMPUTE WITH PREVIOUS DATA
          else
            buffer_features(1) <= (others => '0');
          end if;
        when E2 =>
          if pad(2) = '0' then
            buffer_features(2) <= data_from_mem;  --------- COMPUTE WITH PREVIOUS DATA
          else
            buffer_features(2) <= (others => '0');
          end if;
        when others => null;
      end case;

    end if;
  end process;

  en_reg <= '1' when EA_add = E0 else '0';  -- two clock cycles to execute the MAC

  -------------------------------------------------------------------------------------------------------
  --- PART 2 *********  MACS AND FLOPS ARRAY - ATTENTION :  ARRANGEMENT IS DIFFERENT FROM 2D  ***********
  -------------------------------------------------------------------------------------------------------

  -- the first column does not hava a previous sum
  cols0 : for j in 0 to 2 generate
    mac0 : entity work.mac
      port map(sum     => (others => '0'),
               op1     => weight(j, 0),
               op2     => features(j, 0),
               res_mac => res_mac(j, 0)
               );
  end generate cols0;

  -- second and third column with previous column
  cols12 : for i in 1 to 2 generate
    rows : for j in 0 to 2 generate

      mac12 : entity work.mac
        port map(sum     => reg_mac(j, i-1),  -- previous sum
                 op1     => weight(j, i),
                 op2     => features(j, i),
                 res_mac => res_mac(j, i)
                 );
    end generate rows;
  end generate cols12;

  -- vertical pipe registers 
  pipe_reset <= reset or start_line;  -- ***new*** - reset the internal registers
  reg_r : for i in 0 to 2 generate
    reg_c : for j in 0 to 2 generate

      ireg : entity work.reg
        generic map(INPUT_SIZE => ((INPUT_SIZE*2)+CARRY_SIZE))
        port map(clock => clock, reset => pipe_reset, enable => en_reg,
                 D     => res_mac(j, i),
                 Q     => reg_mac(j, i)
                 );

    end generate reg_c;
  end generate reg_r;

  -- REGISTERS AND ADDERS AFTER THE MAC MATRIX ---------------------
  process(reset, clock)
  begin
    if reset = '1' then
      reg_soma1 <= (others => '0');
      reg_soma2 <= (others => '0');
      reg_soma3 <= (others => '0');
    elsif rising_edge(clock) then
      if en_reg = '1' then
        reg_soma1 <= reg_mac(0, 2);
        reg_soma2 <= reg_soma1 + reg_mac(1, 2);
        reg_soma3 <= reg_soma2 + reg_mac(2, 2) + reg_bias_value;  -- Also add bias
      end if;
    end if;
  end process;

  -- Shift
  --shift_output(19 downto 16) <= (others => '0');

  -- ReLU 
  --shift_output(15 downto 0) <= reg_soma3(19 downto 4) when reg_soma3 > 0 else
  --                             (others => '0');

  shift_output <= reg_soma3 when reg_soma3 > 0 else
                  (others => '0');


  -- Final output
  pixel <= shift_output;

  process(reset, clock)
  begin
    if reset = '1' then
      cont_iterations <= (others => '0');
      change_line <= '0';
    elsif rising_edge(clock) then
      if EA_add = E2 then
        if change_line = '0' then
          if cont_steps > 6  then
            cont_iterations <= cont_iterations + 1;
            if cont_iterations >= CONVS_PER_LINE then
                change_line <= '1';
                cont_iterations <= (others => '0');
            end if;
          end if;
        else
          change_line <= '0';
        end if;
      end if;
    end if;
  end process;

  valid <= '1' when EA_add = UPDATEADD and cont_iterations > 0 else
           '0';
end a1;

