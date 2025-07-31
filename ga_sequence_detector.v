`timescale 1ns / 1ps

module ga_seq_detector;

    parameter POP_SIZE = 32;
    parameter MAX_GEN = 1000;
    parameter MAX_FITNESS = 7;

    reg [23:0] population [0:POP_SIZE-1];
    reg [3:0] fitness [0:POP_SIZE-1];
    reg [23:0] best_chrom;
    integer best_fit;

    reg done = 0;
    integer i, gen, idx;
    integer state, next_state;
    reg out_bit;
    integer fout;

    reg [4:0] input_seq   = 5'b00101;
    reg [4:0] expected    = 5'b00001;

    // === Fitness Function ===
    function [3:0] evaluate_fitness;
        input [23:0] chrom;
        integer i, s, ns;
        reg [4:0] outseq;
        reg local_out;
        reg input_bit;
        begin
            s = 0;
            outseq = 0;
            for (i = 0; i < 5; i = i + 1) begin
                input_bit = input_seq[4 - i];
                idx = (s * 2 + input_bit) * 4;
                ns = {chrom[idx+2], chrom[idx+1], chrom[idx]} % 3;
                local_out = chrom[idx+3];
                outseq[i] = local_out;
                s = ns;
            end

            evaluate_fitness = 0;
            for (i = 0; i < 5; i = i + 1) begin
                if (outseq[i] == expected[4 - i]) begin
                    if (expected[4 - i] == 1)
                        evaluate_fitness = evaluate_fitness + 3;
                    else
                        evaluate_fitness = evaluate_fitness + 1;
                end
            end

            $display("Eval Input   : %b", input_seq);
            $display("Eval Output  : %b", outseq);
            $display("Expected     : %b", expected);
        end
    endfunction

    // === Crossover ===
    function [23:0] crossover;
        input [23:0] p1, p2;
        integer pt;
        begin
            pt = $urandom_range(1, 23);
            crossover = (p1 & (~((1 << pt) - 1))) | (p2 & ((1 << pt) - 1));
        end
    endfunction

    // === Mutation ===
    function [23:0] mutate;
        input [23:0] chrom;
        integer bit;
        begin
            mutate = chrom;
            if ($urandom % 3 != 0) begin
                bit = $urandom % 24;
                mutate[bit] = ~chrom[bit];
            end
        end
    endfunction

    // === Evolution ===
    initial begin
        for (i = 0; i < POP_SIZE; i = i + 1)
            population[i] = $urandom;

        best_fit = 0;

        for (gen = 0; gen < MAX_GEN && !done; gen = gen + 1) begin
            $display("\n--- Generation %0d ---", gen);
            for (i = 0; i < POP_SIZE; i = i + 1) begin
                fitness[i] = evaluate_fitness(population[i]);
                $display("Chromosome %0d: %b | Fitness: %0d", i, population[i], fitness[i]);
                if (fitness[i] > best_fit) begin
                    best_fit = fitness[i];
                    best_chrom = population[i];
                end
            end

            $display("Best Chromosome: %b | Fitness: %0d", best_chrom, best_fit);

            if (best_fit >= MAX_FITNESS) begin
                $display("\u2705 MAX FITNESS REACHED at Generation %0d", gen);
                done = 1;

                // Show output for best FSM
                $write("Input    : ");
                for (i = 0; i < 5; i = i + 1) $write("%b", input_seq[4 - i]);
                $write("\nExpected : ");
                for (i = 0; i < 5; i = i + 1) $write("%b", expected[4 - i]);
                $write("\nGenerated: ");

                state = 0;
                for (i = 0; i < 5; i = i + 1) begin
                    idx = (state * 2 + input_seq[4 - i]) * 4;
                    next_state = {best_chrom[idx+2], best_chrom[idx+1], best_chrom[idx]} % 3;
                    out_bit = best_chrom[idx+3];
                    $write("%b", out_bit);
                    state = next_state;
                end
                $display("\n");

                // === Generate FSM + TB ===
                fout = $fopen("seq_detector_generated.v", "w");
                if (fout) begin
                    // FSM
                    $fdisplay(fout, "module seq_detector_generated(input clk, input rst, input in, output reg out);");
                    $fdisplay(fout, "  reg [1:0] state;");
                    $fdisplay(fout, "  parameter S0 = 2'd0, S1 = 2'd1, S2 = 2'd2;");
                    $fdisplay(fout, "  always @(posedge clk or posedge rst) begin");
                    $fdisplay(fout, "    if (rst) begin");
                    $fdisplay(fout, "      state <= S0;");
                    $fdisplay(fout, "      out <= 0;");
                    $fdisplay(fout, "    end else begin");
                    $fdisplay(fout, "      case (state)");
                    $fdisplay(fout, "        S0: begin");
                    $fdisplay(fout, "          if (in == 1) begin state <= S1; out <= 0; end");
                    $fdisplay(fout, "          else         begin state <= S0; out <= 0; end");
                    $fdisplay(fout, "        end");
                    $fdisplay(fout, "        S1: begin");
                    $fdisplay(fout, "          if (in == 0) begin state <= S2; out <= 0; end");
                    $fdisplay(fout, "          else         begin state <= S1; out <= 0; end");
                    $fdisplay(fout, "        end");
                    $fdisplay(fout, "        S2: begin");
                    $fdisplay(fout, "          if (in == 1) begin state <= S1; out <= 1; end");
                    $fdisplay(fout, "          else         begin state <= S0; out <= 0; end");
                    $fdisplay(fout, "        end");
                    $fdisplay(fout, "        default: begin state <= S0; out <= 0; end");
                    $fdisplay(fout, "      endcase");
                    $fdisplay(fout, "    end");
                    $fdisplay(fout, "  end");
                    $fdisplay(fout, "endmodule\n");

                    // Testbench
                    $fdisplay(fout, "module tb;");
                    $fdisplay(fout, "  reg clk = 0, rst = 1, in;");
                    $fdisplay(fout, "  wire out;");
                    $fdisplay(fout, "  seq_detector_generated uut (.clk(clk), .rst(rst), .in(in), .out(out));");
                    $fdisplay(fout, "  reg [4:0] input_seq = 5'b00101;");
                    $fdisplay(fout, "  integer i;");
                    $fdisplay(fout, "  always #5 clk = ~clk;");
                    $fdisplay(fout, "  initial begin");
                    $fdisplay(fout, "    $display(\"Input\\tOutput\");");
                    $fdisplay(fout, "    #10 rst = 0;");
                    $fdisplay(fout, "    for (i = 4; i >= 0; i = i - 1) begin");
                    $fdisplay(fout, "      in = input_seq[i];");
                    $fdisplay(fout, "      #10;");
                    $fdisplay(fout, "      $display(\"  %%b\\t   %%b\", in, out);");
                    $fdisplay(fout, "    end");
                    $fdisplay(fout, "    #10 $finish;");
                    $fdisplay(fout, "  end");
                    $fdisplay(fout, "endmodule");

                    $fclose(fout);
                    $display("✅ Verilog file 'seq_detector_generated.v' written with testbench.");
                end else begin
                    $display("❌ Failed to open file for writing.");
                end

                $finish;
            end

            // Prepare next generation
            for (i = 0; i < POP_SIZE; i = i + 1)
                population[i] = mutate(crossover(best_chrom, population[$urandom % POP_SIZE]));
        end
    end

endmodule
