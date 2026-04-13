`timescale 1ns / 1ps

module ov7670_capture(
    input  wire       pclk,
    input  wire       vsync,
    input  wire       href,
    input  wire [7:0] d,

    output reg [7:0]  pixel_data,
    output reg        pixel_valid,
    output reg [16:0] addr          // 17-bit: 320*240=76800
);

    reg byte_sel = 1'b0;
    reg [7:0] high_byte = 8'd0;

    reg [9:0]  x       = 10'd0;  // 0..639 (VGA)
    reg [8:0]  y       = 9'd0;   // 0..479 (VGA)
    reg        vsync_d = 1'b0;

    // RGB565 -> grayscale
    // R5=high_byte[7:3], G6={high_byte[2:0],d[7:5]}, B5=d[4:0]
    // gray8 = (R5 + G6 + B5) * 2  (max=250, fits 8-bit)
    wire [6:0] rgb_sum = {2'b0, high_byte[7:3]}
                       + {1'b0, high_byte[2:0], d[7:5]}
                       + {2'b0, d[4:0]};
    wire [7:0] gray8   = {rgb_sum, 1'b0};

    always @(posedge pclk) begin
        pixel_valid <= 1'b0;
        vsync_d     <= vsync;

        if (vsync && !vsync_d) begin
            x        <= 10'd0;
            y        <= 9'd0;
            byte_sel <= 1'b0;
        end
        else if (href) begin
            if (!byte_sel) begin
                high_byte <= d;
                byte_sel  <= 1'b1;
            end else begin
                byte_sel <= 1'b0;

                // 2:1 서브샘플링: x짝수, y짝수 픽셀만 저장
                if (x[0] == 1'b0 && y[0] == 1'b0) begin
                    pixel_data  <= gray8;
                    pixel_valid <= 1'b1;
                    // addr = (y/2)*320 + (x/2)
                    //      = y[8:1]*256 + y[8:1]*64 + x[9:1]
                    addr <= ({1'b0, y[8:1], 8'b0}
                           + {3'b0, y[8:1], 6'b0}
                           + {8'b0, x[9:1]});
                end

                if (x == 10'd639) begin
                    x <= 10'd0;
                    if (y < 9'd479)
                        y <= y + 9'd1;
                end else begin
                    x <= x + 10'd1;
                end
            end
        end
    end

endmodule
