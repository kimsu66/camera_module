`timescale 1ns / 1ps

module ov7670_capture(
    input  wire       pclk,
    input  wire       vsync,
    input  wire       href,
    input  wire [7:0] d,

    output reg [15:0] pixel_data,
    output reg        pixel_valid,
    output reg [14:0] addr
);

    reg byte_sel = 1'b0;
    reg [7:0] high_byte = 8'd0;

    reg [9:0]  x       = 10'd0; // 0~639
    reg [8:0]  y       = 9'd0;  // 0~479
    reg        vsync_d = 1'b0;

    // 수평 4픽셀 평균용 누산기
    // R: 5bit x 4 = 7bit, G: 6bit x 4 = 8bit, B: 5bit x 4 = 7bit
    reg [6:0] r_sum = 7'd0;
    reg [7:0] g_sum = 8'd0;
    reg [6:0] b_sum = 7'd0;

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

                // RGB565: R=high_byte[7:3], G={high_byte[2:0],d[7:5]}, B=d[4:0]

                // 수평 누산: 그룹 첫 픽셀(x%4==0)이면 리셋, 아니면 누적
                if (x[1:0] == 2'b00) begin
                    r_sum <= {2'b0, high_byte[7:3]};
                    g_sum <= {2'b0, high_byte[2:0], d[7:5]};
                    b_sum <= {2'b0, d[4:0]};
                end else begin
                    r_sum <= r_sum + {2'b0, high_byte[7:3]};
                    g_sum <= g_sum + {2'b0, high_byte[2:0], d[7:5]};
                    b_sum <= b_sum + {2'b0, d[4:0]};
                end

                // 그룹 마지막(x%4==3), y도 4의 배수일 때 4픽셀 평균 저장
                // NBA 특성상 r_sum은 앞 3픽셀 합 → 현재 픽셀 직접 합산해서 평균
                if (x[1:0] == 2'b11 && y[1:0] == 2'b00) begin
                    pixel_data <= {
                        (r_sum + {2'b0, high_byte[7:3]})[6:2],
                        (g_sum + {2'b0, high_byte[2:0], d[7:5]})[7:2],
                        (b_sum + {2'b0, d[4:0]})[6:2]
                    };
                    pixel_valid <= 1'b1;
                    addr <= ({1'b0, y[8:2], 7'd0} + {3'b0, y[8:2], 5'd0} + {7'b0, x[9:2]});
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