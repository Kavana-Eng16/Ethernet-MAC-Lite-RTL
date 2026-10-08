// ============================================================
// Module : crc32.v
// Purpose : IEEE 802.3 CRC-32 byte-serial engine
// ============================================================
module crc32 (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        init,      // Synchronous reset to 0xFFFFFFFF
    input  wire        en,        // Process one byte per cycle
    input  wire [7:0]  data_in,   // Byte input (LSB first per 802.3)
    output wire [31:0] crc_out,   // Current CRC value
    output wire [31:0] crc_fcs    // Byte-reversed, bit-inverted FCS
);
    reg [31:0] crc_reg;

    function [31:0] crc32_byte;
        input [31:0] crc;
        input [7:0]  data;
        integer i;
        reg [31:0] c;
        reg inv;
        begin
            c = crc;
            for (i = 0; i < 8; i = i + 1) begin
                inv = c[31] ^ data[i];
                c = {c[30:0], 1'b0} ^ (inv ? 32'h04C11DB7 : 32'h0);
            end
            crc32_byte = c;
        end
    endfunction

    always @(posedge clk) begin
        if (!rst_n || init)
            crc_reg <= 32'hFFFF_FFFF;
        else if (en)
            crc_reg <= crc32_byte(crc_reg, data_in);
    end

    assign crc_out = crc_reg;

    // FCS: reflect the full 32-bit register, then invert all bits.
    // crc_fcs[7:0] is the first FCS byte on the wire (sent LSB first).
    assign crc_fcs = ~{
        {crc_reg[0], crc_reg[1], crc_reg[2], crc_reg[3],
         crc_reg[4], crc_reg[5], crc_reg[6], crc_reg[7]},
        {crc_reg[8], crc_reg[9], crc_reg[10],crc_reg[11],
         crc_reg[12],crc_reg[13],crc_reg[14],crc_reg[15]},
        {crc_reg[16],crc_reg[17],crc_reg[18],crc_reg[19],
         crc_reg[20],crc_reg[21],crc_reg[22],crc_reg[23]},
        {crc_reg[24],crc_reg[25],crc_reg[26],crc_reg[27],
         crc_reg[28],crc_reg[29],crc_reg[30],crc_reg[31]}
    };
endmodule
