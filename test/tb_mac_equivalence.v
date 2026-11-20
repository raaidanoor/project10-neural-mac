`timescale 1ns/1ps
`default_nettype none

module tb_mac_equivalence;
    parameter integer ENTRIES = 16;
    parameter integer ACCW = 24;
    localparam integer INDEX_WIDTH = $clog2(ENTRIES);

    reg clk = 0;
    reg rst_n = 1, clear = 0, valid = 0, write_enable = 0;
    reg signed [7:0] feature = 0, weight = 0;
    reg [INDEX_WIDTH-1:0] index = 0;
    wire baseline_ready, indexed_ready, baseline_valid, indexed_valid;
    wire baseline_overflow, indexed_overflow;
    wire signed [ACCW-1:0] baseline_total, indexed_total;
    wire [ENTRIES-1:0] uncached_slot_select = {{(ENTRIES-1){1'b0}}, 1'b1} << index;

    always #10 clk = ~clk;

    mac_baseline #(.ACCW(ACCW)) baseline (
        .clk(clk), .rst_n(rst_n), .clear(clear), .valid(valid && !write_enable),
        .ready(baseline_ready), .feature(feature), .weight(weight),
        .total(baseline_total), .overflow(baseline_overflow), .result_valid(baseline_valid)
    );

    mac_codebook_core #(.ACCW(ACCW), .ENTRIES(ENTRIES)) indexed (
        .clk(clk), .rst_n(rst_n), .clear(clear), .valid(valid), .ready(indexed_ready),
        .feature(feature), .index(index), .write_enable(write_enable),
        .write_index(index), .write_weight(weight), .read_weight(),
        .total(indexed_total), .overflow(indexed_overflow), .result_valid(indexed_valid)
    );

    reg signed [ACCW-1:0] expected_total;
    reg expected_overflow, expected_hit;
    reg [ENTRIES-1:0] expected_slot_select;
    reg [INDEX_WIDTH+8:0] previous_cache;
    reg [1023:0] vector_path, waveform_path;
    integer vectors, fields, cycle = 0, accepted = 0, expected_pairs;
    integer avoided = 0, lookups = 0;

    initial begin
        if (!$value$plusargs("vectors=%s", vector_path))
            $fatal(1, "Supply a vector file with +vectors");
        if (!$value$plusargs("expected_pairs=%d", expected_pairs))
            $fatal(1, "Supply a pair count with +expected_pairs");
        if ($value$plusargs("waveform=%s", waveform_path)) begin
            $dumpfile(waveform_path);
            $dumpvars(0, tb_mac_equivalence);
        end
        vectors = $fopen(vector_path, "r");
        if (vectors == 0)
            $fatal(1, "Cannot open vector file");

        begin : read_vectors
            forever begin
                @(negedge clk);
                fields = $fscanf(vectors, "%d %d %d %d %d %d %d %d %d %d",
                                 rst_n, clear, write_enable, valid, index, feature,
                                 weight, expected_total, expected_overflow, expected_hit);
                if (fields == -1 || (fields == 0 && $feof(vectors)))
                    disable read_vectors;
                if (fields != 10)
                    $fatal(1, "Malformed vector after cycle %0d", cycle);
                cycle = cycle + 1;
                #1;
                if (baseline_ready !== (rst_n && !clear) ||
                    indexed_ready !== (rst_n && !clear && !write_enable))
                    $fatal(1, "Ready mismatch at cycle %0d", cycle);
                if (!rst_n && (indexed.cache_valid !== 1'b0 ||
                               indexed_total !== 0 || indexed_overflow !== 1'b0 ||
                               indexed_valid !== 1'b0))
                    $fatal(1, "Asynchronous reset failed at cycle %0d", cycle);
                if (indexed.reuse_hit !== expected_hit)
                    $fatal(1, "Cycle %0d index %0d expected hit %b, got %b",
                           cycle, index, expected_hit, indexed.reuse_hit);
                previous_cache = {indexed.cache_valid, indexed.cached_index, indexed.cached_weight};
                @(posedge clk);
                if (valid && indexed_ready) begin
                    accepted = accepted + 1;
                    if (indexed.reuse_hit)
                        avoided = avoided + 1;
                    if (|indexed.slot_select)
                        lookups = lookups + 1;
                    expected_slot_select = 0;
                    if (!expected_hit)
                        expected_slot_select[index] = 1'b1;
                    if (indexed.slot_select !== expected_slot_select)
                        $fatal(1, "Cycle %0d expected slot selects %b, got %b",
                               cycle, expected_slot_select, indexed.slot_select);
                end
                #1;
                if ((clear || write_enable) && indexed.cache_valid !== 1'b0)
                    $fatal(1, "Cache remained valid after clear or write at cycle %0d", cycle);
                if (rst_n && !clear && !write_enable && !valid &&
                    {indexed.cache_valid, indexed.cached_index, indexed.cached_weight} !== previous_cache)
                    $fatal(1, "Cache changed during idle at cycle %0d", cycle);
                if (baseline_valid !== (valid && baseline_ready && !write_enable) ||
                    indexed_valid !== baseline_valid ||
                    baseline_total !== expected_total || indexed_total !== expected_total ||
                    baseline_overflow !== expected_overflow || indexed_overflow !== expected_overflow)
                    $fatal(1, "Cycle %0d expected total/overflow %0d/%b, baseline %0d/%b, indexed %0d/%b",
                           cycle, expected_total, expected_overflow, baseline_total,
                           baseline_overflow, indexed_total, indexed_overflow);
            end
        end
        $fclose(vectors);
        if (accepted != expected_pairs)
            $fatal(1, "Expected %0d accepted pairs, got %0d", expected_pairs, accepted);
        if (lookups + avoided != accepted)
            $fatal(1, "Expected one lookup or hit per accepted pair");
        $display("PASS: %0d entries, %0d-bit accumulator, %0d accepted pairs",
                 ENTRIES, ACCW, accepted);
        $display("Lookups performed=%0d avoided=%0d reuse_fraction=%0.6f",
                 lookups, avoided, $itor(avoided) / accepted);
        $finish;
    end
endmodule

`default_nettype wire
