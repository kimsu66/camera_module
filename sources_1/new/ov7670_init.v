`timescale 1ns / 1ps

module ov7670_init(
    input  wire clk,      // 100MHz
    input  wire resetn,
    output reg  scl,
    inout  wire sda,
    output reg  done
);

    // -----------------------------------------
    // SCCB SDA open-drain style
    // -----------------------------------------
    reg sda_oe;
    reg sda_out;
    assign sda = sda_oe ? sda_out : 1'bz;

    // -----------------------------------------
    // slow tick for SCCB (~100kHz-ish)
    // 100MHz / 500 = 200kHz toggle
    // -----------------------------------------
    reg [8:0] clk_div = 9'd0;
    reg tick = 1'b0;

    always @(posedge clk) begin
        if (clk_div == 9'd499) begin
            clk_div <= 9'd0;
            tick    <= 1'b1;
        end else begin
            clk_div <= clk_div + 9'd1;
            tick    <= 1'b0;
        end
    end

    // -----------------------------------------
    // init ROM
    // first: COM7 reset = 0x80
    // then wait
    // then QVGA YUV settings
    // -----------------------------------------
    reg [7:0] rom_addr [0:10];
    reg [7:0] rom_data [0:10];

    initial begin
        rom_addr[0]  = 8'h12; rom_data[0]  = 8'h80; // COM7: reset
        rom_addr[1]  = 8'h11; rom_data[1]  = 8'h00; // CLKRC: no prescale
        rom_addr[2]  = 8'h12; rom_data[2]  = 8'h04; // COM7: RGB output
        rom_addr[3]  = 8'h40; rom_data[3]  = 8'hD0; // COM15: full range + RGB565
        rom_addr[4]  = 8'h3A; rom_data[4]  = 8'h04; // TSLB: normal sequence
        rom_addr[5]  = 8'h3D; rom_data[5]  = 8'h88; // COM13: default-ish
        rom_addr[6]  = 8'h0C; rom_data[6]  = 8'h00; // COM3: no scaling
        rom_addr[7]  = 8'h3E; rom_data[7]  = 8'h00; // COM14: normal PCLK
        // rom_addr[8]  = 8'h70; rom_data[8]  = 8'h3A; // SCALING_XSC: test_pattern[0]=1
        // rom_addr[9]  = 8'h71; rom_data[9]  = 8'h35; // SCALING_YSC: test_pattern[1]=0 => 8-bar color bar
        rom_addr[10] = 8'h15; rom_data[10] = 8'h00; // COM10: default polarity
    end

    localparam DEV_WR = 8'h42;

    reg [3:0]  state = 0;
    reg [3:0]  bit_cnt = 0;
    reg [7:0]  shreg = 8'd0;
    reg [3:0]  reg_index = 0;
    reg [23:0] wait_cnt = 0;

    localparam S_IDLE      = 0,
               S_START1    = 1,
               S_START2    = 2,
               S_LOAD_DEV  = 3,
               S_SEND_DEV0 = 4,
               S_SEND_DEV1 = 5,
               S_LOAD_REG  = 6,
               S_SEND_REG0 = 7,
               S_SEND_REG1 = 8,
               S_LOAD_DAT  = 9,
               S_SEND_DAT0 = 10,
               S_SEND_DAT1 = 11,
               S_STOP1     = 12,
               S_STOP2     = 13,
               S_WAIT1MS   = 14,
               S_DONE      = 15;

    initial begin
        scl     = 1'b1;
        sda_oe  = 1'b1;
        sda_out = 1'b1;
        done    = 1'b0;
    end

    always @(posedge clk) begin
        if (!resetn) begin
            state    <= S_IDLE;
            scl      <= 1'b1;
            sda_oe   <= 1'b1;
            sda_out  <= 1'b1;
            done     <= 1'b0;
            reg_index<= 0;
            wait_cnt <= 0;
        end else if (tick) begin
            case (state)
                S_IDLE: begin
                    done <= 1'b0;
                    scl <= 1'b1;
                    sda_oe <= 1'b1;
                    sda_out <= 1'b1;
                    state <= S_START1;
                end

                S_START1: begin
                    scl <= 1'b1;
                    sda_out <= 1'b0;
                    state <= S_START2;
                end

                S_START2: begin
                    scl <= 1'b0;
                    state <= S_LOAD_DEV;
                end

                S_LOAD_DEV: begin
                    shreg <= DEV_WR;
                    bit_cnt <= 4'd7;
                    state <= S_SEND_DEV0;
                end

                S_SEND_DEV0: begin
                    sda_oe  <= 1'b1;
                    sda_out <= shreg[bit_cnt];
                    scl <= 1'b0;
                    state <= S_SEND_DEV1;
                end

                S_SEND_DEV1: begin
                    scl <= 1'b1;
                    if (bit_cnt == 0) begin
                        scl <= 1'b0;
                        sda_oe <= 1'b0; // ACK slot ignore
                        state <= S_LOAD_REG;
                    end else begin
                        bit_cnt <= bit_cnt - 1'b1;
                        state <= S_SEND_DEV0;
                    end
                end

                S_LOAD_REG: begin
                    sda_oe <= 1'b1;
                    shreg <= rom_addr[reg_index];
                    bit_cnt <= 4'd7;
                    state <= S_SEND_REG0;
                end

                S_SEND_REG0: begin
                    sda_out <= shreg[bit_cnt];
                    scl <= 1'b0;
                    state <= S_SEND_REG1;
                end

                S_SEND_REG1: begin
                    scl <= 1'b1;
                    if (bit_cnt == 0) begin
                        scl <= 1'b0;
                        sda_oe <= 1'b0; // ACK slot ignore
                        state <= S_LOAD_DAT;
                    end else begin
                        bit_cnt <= bit_cnt - 1'b1;
                        state <= S_SEND_REG0;
                    end
                end

                S_LOAD_DAT: begin
                    sda_oe <= 1'b1;
                    shreg <= rom_data[reg_index];
                    bit_cnt <= 4'd7;
                    state <= S_SEND_DAT0;
                end

                S_SEND_DAT0: begin
                    sda_out <= shreg[bit_cnt];
                    scl <= 1'b0;
                    state <= S_SEND_DAT1;
                end

                S_SEND_DAT1: begin
                    scl <= 1'b1;
                    if (bit_cnt == 0) begin
                        scl <= 1'b0;
                        sda_oe <= 1'b0; // ACK slot ignore
                        state <= S_STOP1;
                    end else begin
                        bit_cnt <= bit_cnt - 1'b1;
                        state <= S_SEND_DAT0;
                    end
                end

                S_STOP1: begin
                    sda_oe <= 1'b1;
                    sda_out <= 1'b0;
                    scl <= 1'b1;
                    state <= S_STOP2;
                end

                S_STOP2: begin
                    sda_out <= 1'b1;
                    if (reg_index == 0) begin
                        wait_cnt <= 20'd1000000; // ~10ms @100MHz
                        state <= S_WAIT1MS;
                    end else if (reg_index == 10) begin
                        state <= S_DONE;
                    end else begin
                        reg_index <= reg_index + 1'b1;
                        state <= S_START1;
                    end
                end

                S_WAIT1MS: begin
                    if (wait_cnt == 0) begin
                        reg_index <= reg_index + 1'b1;
                        state <= S_START1;
                    end else begin
                        wait_cnt <= wait_cnt - 1'b1;
                    end
                end

                S_DONE: begin
                    done <= 1'b1;
                    scl <= 1'b1;
                    sda_oe <= 1'b1;
                    sda_out <= 1'b1;
                    state <= S_DONE;
                end
            endcase
        end
    end

endmodule