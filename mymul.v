`include "defines.vh"
module mymul (
  input wire clk,
  input wire rst,
  input wire mul_signed, //signed is 1, unsigned is 0
  input wire [31:0] ina,
  input wire [31:0] inb,
  input wire start_i,						//是否开始乘法运算
  output reg [63:0] result_o,
  output reg ready_o                        
);
	reg [5:0] cnt;							//记录进行了几轮
	reg[63:0] middle;
	reg[63:0] wyq;

	reg [1:0] state;						//乘法器处于的状态	
	reg[31:0] temp_op1;
	reg[31:0] temp_op2;

	always @ (posedge clk) begin
		if (rst) begin
			state <= `MulFree;
			result_o <= {`ZeroWord,`ZeroWord};
			ready_o <= `MulResultNotReady;
		end else begin
			case(state)
			
				`MulFree: begin			//乘法器空闲
					if (start_i == `MulStart) begin
							state <= `MulOn;					
							cnt <= 6'b000000;
							if(mul_signed == 1'b1 && ina[31] == 1'b1) begin			//被乘数为负数
								temp_op1 = ~ina + 1;
							end else begin
								temp_op1 = ina;
							end
							if (mul_signed == 1'b1 && inb[31] == 1'b1 ) begin		//乘数为负数
								temp_op2 = ~inb + 1;
							end else begin
								temp_op2 = inb;
							end

					wyq <= {`ZeroWord,temp_op1};
					middle <= {`ZeroWord,`ZeroWord};
						
					end else begin
						ready_o <= `MulResultNotReady;
						result_o <= {`ZeroWord, `ZeroWord};
					end
				end
				
		
				`MulOn: begin				
						if(cnt != 6'b100000) begin
							if (temp_op2[0] == 1'b1) begin
								middle <= wyq + middle;
								wyq = wyq<<1;
								temp_op2 = temp_op2>>1;
							//如果是1，就相加，如果是0就跳过
							end else begin
								wyq = wyq<<1;
								temp_op2 = temp_op2>>1;
							end
							cnt <= cnt +1;		//运算次数
						end	else begin
							if ((mul_signed == 1'b1) && ((ina[31] ^ inb[31]) == 1'b1)) begin
								middle <= ~middle + 1;
							end
							state <= `MulEnd;
							cnt <= 6'b000000;
						end
				end


				`MulEnd: begin			//除法结束
					result_o <= middle;
					ready_o <= `MulResultReady;
					if (start_i == `MulStop) begin
						state <= `MulFree;
						ready_o <= `MulResultNotReady;
						result_o <= {`ZeroWord, `ZeroWord};
					end
				end
				
			endcase
		end
	end


endmodule

