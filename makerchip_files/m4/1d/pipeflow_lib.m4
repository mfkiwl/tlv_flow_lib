m4_hide(['
/*
Copyright (c) 2014, Intel Corporation

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

    * Redistributions of source code must retain the above copyright notice,
      this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above copyright
      notice, this list of conditions and the following disclaimer in the
      documentation and/or other materials provided with the distribution.
    * Neither the name of Intel Corporation nor the names of its contributors
      may be used to endorse or promote products derived from this software
      without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE
FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
*/

m4_nothing(['// A TLV M4 library file for pipeflows.
// Relies on macros defined in generic_tlv.m4 and rw_tlv.m4.
// See comments in rw_tlv.m4 describing conventions for TLV M4 library files.
//
// TODO: Move to a different file.
//


//=================
// Arbitration
//

// Credit counter.
// m4_credit_counter(CreditState, MAX_BIT, MAX_CREDIT, reset, incr_sig, decr_sig, ind)
// Eg: m4+credit_counter($Credit, 4, 10, /top|rs<>0$reset, $credit_returned, $credit_consumed)
'])m4_define_plus2(['credit_counter'], ['['
   $credit_upd = $']['4 || ($']['5 ^ $']['6);
   ?$credit_upd
      $']['1[$']['2:0] <=
           $']['4
              ? m4_eval($']['2 + 1)'d['']$']['3
              : ($']['1 + ($']['5 ? m4_eval($']['2 + 1)'d1 : '1));']'], ['{$_Credit}'], ['{#_MAX_BIT}'], ['{#_MAX_CREDIT}'], ['{$_reset}'], ['{$_incr}'], ['{$_decr}'])m4_dnl
m4_nothing(['


'])m4_nothing(['// A backpressured flop stage.
// m4_bp_stage(top, in_pipe, in_stage, out_pipe, out_stage[, indentation_str, b_latch, a_latch])
//
// Parameters:
//   top:             eg: 'top'
//   in/out_pipe/stage: As below.
//   indentation_str:   eg: '   ' to provide 1 additional level of indentation
//
// This creates backpressure and recirculation for a transaction going from in_pipe to out_pipe.
//
// |in_pipe
//   @in_stage|\  +--+
//      ------| | |  |  |out_pipe@out_stage
//            | |-|  |-+----
//         +--| | |/\| |
//         |  |/  +--+ |
//         |           |
//         +-----------+
//
// Input interface:
//   |in_pipe
//      @in_stage  (minus a phase for SELF)
//         $trans_avail   // A transaction is available for consumption.
//         ?$trans_valid = $trans_avail && ! $blocked
//            $ANY        // input transaction
//   |out_pipe
//      @out_stage
//         $blocked       // The corresponding output transaction, if valid, cannot be consumed
//                        // and will recirculate.
// Output signals:
//   |in_pipe
//      @in_stage
//         $blocked       // The corresponding input transaction, if valid, cannot be consumed
//                        // and must recirculate.
//   |out_pipe
//      @out_stage
//         $trans_avail   // A transaction is available for consumption.
//                        // (Actually, @out_stage-1, but expect consumption in @out_stage.)
//         ?($trans_avail && ! $blocked)
//            $ANY        // Output transaction
//
// This macro also supports SELF (Synchronous ELastic Flow) pipelines that are latch-based pipelines
// with backpressure at every phase.
// In this case, the input stage is the cycle feeding the recirculation, and the output stage is
// the cycle of the recirculation + 1.  Input and output stages are L for B-phase stages.
// These additional optional parameters exist to support it:
//   b_latch:           1 for a SELF stage that is recirculating across a  B-latch (0 default).
//   a_latch:           1 for a SELF stage that is recirculating across an A-latch (0 default).
// Internals:
//   pre_latch_phase:             'L' for A-latch stage.
//   post_latch_phase:            'L' for B-latch stage.
'])m4_define_plus2(['bp_stage'], ['['
   m4_pushdef(['m4_b_latch'],   m4_ifelse($']['6, 1, 1, 0))
   m4_pushdef(['m4_a_latch'],   m4_ifelse($']['7, 1, 1, 0))
   m4_pushdef(['m4_pre_latch_phase'],  m4_ifelse(m4_a_latch, 1, L,))
   m4_pushdef(['m4_post_latch_phase'], m4_ifelse(m4_b_latch, 1, L,))
   $']['4
      @m4_stage_eval($']['5 - m4_b_latch - 1)['']m4_post_latch_phase
         $trans_avail = (>>1$trans_avail && >>1$blocked) ||  // Recirc'ed or
                        // Above is recomputation of $recirc to avoid a flop.
                        // For SELF, its in the same stage, and is redundant computation.
                        $']['1$']['2>>m4_align($']['3, $']['5 - 1)$trans_avail; // Incoming available
         //$first_avail = $trans_avail && ! >>1$blocked;  // Transaction is newly available.
      @m4_stage_eval($']['5 - 1)m4_pre_latch_phase
         ?$trans_avail  // Physically, $first_avail && *reset_b for functional gating in
                        // place of recirculation.
            $ANY =
               >>1$recirc ? >>1$ANY
                          : $']['1$']['2>>m4_align($']['3, $']['5 - 1)$ANY;
      @m4_stage_eval($']['5 - m4_b_latch)['']m4_post_latch_phase
         $recirc = $trans_avail && $blocked;  // Available transaction that is blocked; must recirc.
         // A valid for external transaction processing.
         $trans_valid = $trans_avail && ! $blocked;
         `BOGUS_USE($trans_valid)
   $']['2
      @m4_stage_eval($']['3 - m4_b_latch)['']m4_post_latch_phase
         $blocked = $']['1$']['4>>m4_align($']['5, $']['3)$recirc;
              // This trans is blocked (whether valid or not) if the next stage is recirculating.
   ']'], ['{/_top}'], ['{|_in_pipe}'], ['{@_in_stage}'], ['{|_out_pipe}'], ['{@_out_stage}'], ['{#_b_latch}'], ['{#_a_latch}'])m4_dnl
m4_nothing(['

'])m4_nothing(['// A backpressured pipeline.
// m4_bp_pipeline(name, input_stage, output_stage[, indentation_str])
//
// This creates recirculation between input_stage and output_stage
//   ((output_stage - input_stage - 1) recirculations).  Each stage from (input_stage + 1)
//   to output_stage is a pipeline for transactions from a recirculation mux in @0
//   (soon to be clock gating with a @0 enable), where transaction logic is intended for @1.
//   If there is any unoccupied stage, all prior stages will progress.
//   So backpressure on |name['']output_stage@0$blocked is immediately visible on
//   |name['']input_stage@0$blocked if all stages are occupied.  |name['']output_stage$blocked
//   should be available early enough in @0, and |name['']input_stage$blocked should
//   generally be consumed in @1.
//
// Transaction functionality should be placed in:
//   |name['']input_stage through |name['']output_stage @1.
//
// Input interface:
//   |name['']input_stage
//      @1
//         $trans_avail   // A transaction is available for consumption.
//         ?trans_valid = $trans_avail && ! $blocked
//            $ANY        // input transaction.
//   |name['']output_stage
//      @1
//         $blocked       // The corresponding output transaction, if valid, cannot be consumed
//                        // and will recirculate.
// Output signals:
//   |name['']input_stage
//      @1
//         $blocked       // The corresponding input transaction, if valid, cannot be consumed
//                        // and must recirculate.
//   |name['']output_stage
//      @1
//         $trans_avail   // A transaction is available for consumption.
'])m4_define_plus2(['bp_pipeline'], ['['
   m4_forloop(['m4_stage'], m4_incr($']['2), $']['3, ['
   m4_bp_stage(['   '], ['UNUSED1'], ['UNUSED2'], ['   // Instantiated from ']m4_FILE[', ']']']m4___line__['['[' as: m4+bp_stage(/top, ']$']['1['['']m4_decr(m4_stage), 1, ']$']['1['['']m4_stage, 1)'], /top, ']$']['1['['']m4_decr(m4_stage), 1, ']$']['1['['']m4_stage, 1)
   '])']'], ['{|_name}'], ['{@_input_stage}'], ['{@_output_stage}'])m4_dnl
m4_nothing(['


'])\source m4_escaped_string(m4_FILE) 216['']m4_new_line()// ==========================================================
//
// Stall Pipeline
//

// One cycle of a stall pipeline.
// m4_stall_stage(top, in_pipe, in_stage, mid_pipe, mid_stage, out_pipe, out_stage[, indentation_str])
//   top:                   eg: 'top'
//   in/mid/out_pipe/stage: The pipeline name and stage number of the input (A-phase) stage
//                          and the output stage.
//   indentation_str:       eg: '   ' to provide 1 additional level of indentation
//
// This creates recirculation for a transaction going from in_pipe to out_pipe,
// where in_pipe/stage is one cycle from out_pipe/stage without backpressure.
//
// Currently, this uses recirculation, but it is intended to be modified to use flop enables
// to hold the transactions.
//
// Input interface:
//   |in_pipe
//      @in_stage
//         $trans_avail   // A transaction is available for consumption.
//         ?trans_valid = $trans_avail && ! $blocked
//            /trans
//               $ANY     // input transaction
//   |out_pipe
//      @out_stage
//         $blocked       // The corresponding output transaction, if valid, cannot be consumed
//                        // and will recirculate.
// Output signals:
//   |in_pipe
//      @in_stage
//         $blocked       // The corresponding input transaction, if valid, cannot be consumed
//                        // and must recirculate.
//   |out_pipe
//      @out_stage
//         $trans_avail   // A transaction is available for consumption.
//         ?trans_valid   // $trans_avail && ! $blocked
//            /trans
//               $ANY     // Output transaction
//
m4_define_plus(['m4_stall_stage'], ['
m4_pushdef(['m4_top'],       ['$5'])
m4_pushdef(['m4_in_pipe'],   ['$6'])
m4_pushdef(['m4_in_stage'],  ['$7'])
m4_pushdef(['m4_out_pipe'],  ['$8'])
m4_pushdef(['m4_out_stage'], ['$9'])

'], m4___file__, m4___line__, ['
   |m4_in_pipe
      @m4_in_stage
         $blocked = /m4_top|m4_out_pipe<>0$blocked;
   |m4_out_pipe
      @m4_out_stage
         $trans_avail = $blocked ? <<1$trans_avail : /m4_top|m4_in_pipe>>1$trans_avail;
         $trans_valid = $trans_avail && !$blocked;
         ?$trans_valid
            /trans_hold
               $ANY = |m4_out_pipe$blocked ? <<1$ANY : /m4_top|m4_in_pipe/trans>>1$ANY;
         ?$trans_avail
            /trans
               $ANY = |m4_out_pipe/trans_hold$ANY;
'],

['
m4_popdef(['m4_top'])
m4_popdef(['m4_in_pipe'])
m4_popdef(['m4_in_stage'])
m4_popdef(['m4_out_pipe'])
m4_popdef(['m4_out_stage'])
'])


// A Stall Pipeline.
// m4_stall_pipeline(top, name, first_cycle, last_cycle)
//
// Transaction logic can be defined externally, and spread across the stall pipeline.
//
// Input interface:
//   |m4_name['']m4first_cycle
//      @0
//         $trans_avail   // A transaction is available for consumption.
//         ?trans_valid = $trans_avail && ! $blocked
//            /trans
//               $ANY     // input transaction.
//   |m4_name['']m4_last_cycle
//      @0
//         $blocked       // The stall signal.
// Output signals:
//   |m4_in_pipe
//      @0
//         $blocked       // Identical to the stall signal.
//   |m4_name['']m4_last_cycle
//      @0
//         $trans_avail   // A transaction is available for consumption.
//         $trans_valid   // The transaction is valid.
//         ?$trans_valid
//            /trans
//               $ANY
//
m4_define_plus(['m4_stall_pipeline'], ['
m4_pushdef(['m4_top'],         ['$5'])
m4_pushdef(['m4_name'],        ['$6'])
m4_pushdef(['m4_first_cycle'], ['$7'])
m4_pushdef(['m4_last_cycle'],  ['$8'])

'], m4___file__, m4___line__, ['m4_dnl
m4_forloop(['m4_cycle'], m4_first_cycle, m4_last_cycle, ['
   m4_stall_stage(['$1   '], ']']m4___file__['[', ']']m4___line__['[', ['m4_['']stall_stage(...)'], m4_top, m4_name['']m4_cycle, 0, m4_name['']m4_eval(m4_cycle + 1), 0)'])
'],

['
m4_popdef(['m4_top'])
m4_popdef(['m4_name'])
m4_popdef(['m4_first_cycle'])
m4_popdef(['m4_last_cycle'])
'])





// ==========================================================
//
// SELF (Synchronous ELastic Flow) pipelines.
//

// One cycle of a SELF pipeline.
// m4_self_cycle(top, in_pipe, in_stage, mid_pipe, mid_stage, out_pipe, out_stage[, indentation_str])
//   top:                   eg: 'top'
//   in/mid/out_pipe/stage: The pipeline name and stage number of the input (A-phase) stage
//                          and the output stage.
//   indentation_str:       eg: '   ' to provide 1 additional level of indentation
//
// This creates backpressure and recirculation for a transaction going from in_pipe to out_pipe,
// where in_pipe/stage is one cycle from out pipe/stage without backpressure.  There are two
// stages of backpressure, one A-phase, and one B-phase.
//
// Currently, this uses recirculation, but it is intended to be modified to use latch enables
// to hold the transactions.
//
// Input interface:
//   |in_pipe
//      @in_stage
//         $trans_avail   // A transaction is available for consumption.
//         ?trans_valid = $trans_avail && ! $blocked
//            $ANY        // input transaction
//   |out_pipe
//      @out_stage
//         $blocked       // The corresponding output transaction, if valid, cannot be consumed
//                        // and will recirculate.
// Output signals:
//   |in_pipe
//      @in_stage
//         $blocked       // The corresponding input transaction, if valid, cannot be consumed
//                        // and must recirculate.
//   |out_pipe
//      @out_stage
//         $trans_avail   // A transaction is available for consumption.
//         ?trans_valid   // $trans_avail && ! $blocked
//            $ANY        // Output transaction
m4_define_plus(['m4_self_cycle'], ['
m4_pushdef(['m4_top'],       ['$5'])
m4_pushdef(['m4_in_pipe'],   ['$6'])
m4_pushdef(['m4_in_stage'],  ['$7'])
m4_pushdef(['m4_mid_pipe'],  ['$8'])
m4_pushdef(['m4_mid_stage'], ['$9'])
m4_pushdef(['m4_out_pipe'],  ['$10'])
m4_pushdef(['m4_out_stage'], ['$11'])

'], m4___file__, m4___line__, ['
m4_bp_stage(m4_top, m4_in_pipe,  m4_in_stage,           m4_mid_pipe, m4_mid_stage, ['$1'], 1, 0)  // Not sure indentation is passed right.
m4_bp_stage(m4_top, m4_mid_pipe, m4_decr(m4_mid_stage), m4_out_pipe, m4_out_stage, ['$1'], 0, 1)
'],

['
m4_popdef(['m4_top'])
m4_popdef(['m4_in_pipe'])
m4_popdef(['m4_in_stage'])
m4_popdef(['m4_mid_pipe'])
m4_popdef(['m4_mid_stage'])
m4_popdef(['m4_out_pipe'])
m4_popdef(['m4_out_stage'])
'])


// A SELF pipeline.
// m4_self_pipeline(top, name, in_pipe, in_stage, first_phase, last_phase[, out_pipe, out_stage])
//
// m4_first_phase should be odd, m4_last_phase should be even.
// This creates recirculation from m4_first_phase to m4_last_phase.
//   (m4_last_phase - m4_first_phase + 1 recirculations).  Each phase from m4_first_phase
//   to m4_last_phase is a pipeline for transactions from a recirculation mux in @0/@0L (odd/even
//   phase) (soon to be clock gating with a @0/@0L enable), where transaction logic is intended
//   for @0L/@1 (odd/even).
//
// Transaction logic can be defined externally, and spread across the SELF pipeline.
// The transaction should come in on:
//   |m4_in_pipe@m4_in_stage (would align to: |m4_name[''](m4_first_phase-1)@1)
// and transaction logic placed in:
//   |m4_name['']m4_phase@0L(if even phase)/1(if odd phase)
// and the transaction leaves from:
//   |m4_name['']m4_last_phase@0 or |m4_out_pipe@(m4_out_stage-1)
//
// Input interface:
//   |m4_in_pipe
//      @m4_in_stage
//         $trans_avail   // A transaction is available for consumption.
//         ?trans_valid = $trans_avail && ! $blocked
//            $ANY        // input transaction.
//   |m4_name['']m4_last_phase  (or |m4_out_pipe@(m4_out_stage-1))
//      @1
//         $blocked       // The corresponding output transaction, if valid, cannot be consumed
//                        // and will recirculate.
// Output signals:
//   |m4_in_pipe
//      @m4_in_stage
//         $blocked       // The corresponding input transaction, if valid, cannot be consumed
//                        // and must recirculate.
//   |m4_name['']m4_last_phase  (or |m4_out_pipe@(m4_out_stage-1))
//      @1
//         $trans_avail   // A transaction is available for consumption.
m4_define_plus(['m4_self_pipeline'], ['
m4_pushdef(['m4_top'],         ['$5'])
m4_pushdef(['m4_name'],        ['$6'])
m4_pushdef(['m4_in_pipe'],     ['$7'])
m4_pushdef(['m4_in_stage'],    ['$8'])
m4_pushdef(['m4_first_phase'], ['$9'])
m4_pushdef(['m4_last_phase'],  ['$10'])
m4_pushdef(['m4_out_pipe'],    ['$11'])
m4_pushdef(['m4_out_stage'],   ['$12'])

'], m4___file__, m4___line__, ['
m4_forloop(['m4_cycle'], 0, m4_eval((m4_last_phase - m4_first_phase) / 2), ['
m4_define(['m4_phase'], m4_eval(m4_first_phase + (m4_cycle * 2)))
m4_define(['m4_in_p'], m4_ifelse(m4_cycle, 0, m4_in_pipe,  m4_name['']m4_decr(m4_phase)))
m4_define(['m4_in_s'], m4_ifelse(m4_cycle, 0, m4_in_stage, 1))
m4_define(['m4_out_p'], m4_ifelse(m4_ifelse(m4_out_pipe, , NO_MATCH, )m4_cycle, m4_eval((m4_last_phase - m4_first_phase) / 2), m4_out_pipe, m4_name['']m4_incr(m4_phase)))
m4_define(['m4_out_s'], m4_ifelse(m4_ifelse(m4_out_stage, , NO_MATCH, )m4_cycle, m4_eval((m4_last_phase - m4_first_phase) / 2), m4_out_stage, 1))
m4_self_cycle(['$1'], ']']m4___file__['[', ']']m4___line__['[', ['m4_['']self_cycle(...)'], m4_top, m4_in_p, m4_in_s, m4_name['']m4_phase, 1, m4_out_p, m4_out_s)
'])'],

['
m4_popdef(['m4_top'])
m4_popdef(['m4_name'])
m4_popdef(['m4_in_pipe'])
m4_popdef(['m4_in_stage'])
m4_popdef(['m4_first_phase'])
m4_popdef(['m4_last_phase'])
m4_popdef(['m4_out_pipe'])
m4_popdef(['m4_out_stage'])
'])





// A simple flop-based FIFO with entry-granular clock gating.
// Note: Simulation is less efficient due to the explicit clock gating.
//
// m4+flop_fifo_v2(top, in_pipe, in_stage, out_pipe, out_stage, depth, trans_hier [, high_water])
//
// Input interface:
//   |in_pipe
//      @in_stage
//         $reset         // A reset signal.
//         $trans_avail   // A transaction is available for consumption.
//         $trans_valid   // = $trans_avail && ! $blocked;
//         ?$trans_valid
//            $ANY        // Input transaction (under trans_hier if non-empty)
//   |out_pipe
//      @out_stage
//         $blocked       // The corresponding output transaction, if valid, cannot be consumed
//                        // and will recirculate.
// Output interface:
//   |in_pipe
//      @in_stage
//         $blocked       // The corresponding input transaction, if valid, cannot be consumed
//                        // and must recirculate.
//   |out_pipe
//      @out_stage
//         $trans_avail   // A transaction is available for consumption.
//         $trans_valid = $trans_avail && ! $blocked
//      @out_stage
//         ?$trans_valid
//            $ANY        // Output transaction (under trans_hier if given)
//
// Three interfaces are available for backpressure.  The interface above shows the $blocked interface, but
// any of the three may be used:
//   1) $blocked: Backpressure within a cycle.
//   2) $full or $ValidCount: Reflect a high-water mark that can be used as backpressure.
//      Useful for sources that are not aware of other possible sources filling the FIFO.
//   3) |out_pipe$trans_valid: Can be used to track credits for the FIFO.  See m4_credit_counter(..).
//
// The head and tail "pointers" are maintained in the following state.  Below shows allocation of 4 entries
// followed by deallocation of 4 entries in a 4-entry FIFO.  The valid mask for the entries is $state
// modified by $two_valid, which extends the $state mask by an entry.  This technique uses n+(n log2) state bits (vs.
// (n log2)*2 for pointers or n*2 for decoded pointers).  It does not require decoders for read/write.
//
// $ValidCount 012343210
//          /0 011110000
//   $state< 1 000111000
//          |2 000011100
//          \3 000000010
//  $two_valid 001111100
// Computed:
//      $empty 100000001
//       $full 000010000  (Assuming default m4_high_water.)
//
// Fifo bypass goes through a mux with |in_pipe@in_at aligned to |out_pipe@out_at.

m4_unsupported(['m4_flop_fifo'], 1)
m4_define_plus(['m4_flop_fifo_v2'], ['
m4_pushdef(['m4_top'],       ['$5'])
m4_pushdef(['m4_in_pipe'],   ['$6'])
m4_pushdef(['m4_in_at'],     ['$7'])
m4_pushdef(['m4_out_pipe'],  ['$8'])
m4_pushdef(['m4_out_at'],    ['$9'])
m4_pushdef(['m4_depth'],     ['$10'])
m4_pushdef(['m4_trans_hier'],['$11'])  // Eg: ['/flit'] or ['']
m4_pushdef(['m4_high_water'],['$12'])  // Default to 0.  Number of additional entries beyond full.

m4_pushdef(['m4_ptr_width'], \$clog2(m4_depth))
m4_pushdef(['m4_counter_width'], \$clog2((m4_depth)+1))
m4_pushdef(['m4_bypass_align'], m4_align(m4_out_at, m4_in_at))
m4_pushdef(['m4_reverse_bypass_align'], m4_align(m4_in_at, m4_out_at))
m4_pushdef(['m4_trans_ind'], m4_ifelse(m4_trans_hier, [''], [''], ['   ']))

'], m4___file__, m4___line__, ['
   //|default
   //   @0
   \SV_plus
      localparam bit [m4_counter_width-1:0] full_mark_['']m4_plus_inst_id = m4_depth - m4_ifelse(m4_high_water, [''], 0, ['m4_high_water']);

   // FIFO Instantiation

   // Hierarchy declarations
   |m4_in_pipe
      /entry[(m4_depth)-1:0]
   |m4_out_pipe
      /entry[(m4_depth)-1:0]

   // Hierarchy
   |m4_in_pipe
      @m4_in_at
         $out_blocked = /m4_top|m4_out_pipe>>m4_bypass_align$blocked;
         $blocked = >>1$full && $out_blocked;
         `BOGUS_USE($blocked)   // Not required to be consumed elsewhere.
         $would_bypass = >>1$empty;
         $bypass = $would_bypass && ! $out_blocked;
         $push = $trans_valid && ! $bypass;
         $grow   =   $trans_valid &&   $out_blocked;
         $shrink = ! $trans_avail && ! $out_blocked && ! >>1$empty;
         $valid_count[m4_counter_width-1:0] = $reset ? '0
                                                     : >>1$valid_count + (
                                                          $grow   ? { {(m4_counter_width-1){1'b0}}, 1'b1} :
                                                          $shrink ? '1
                                                                  : '0
                                                       );
         // At least 2 valid entries.
         //$two_valid = | $ValidCount[m4_counter_width-1:1];
         // but logic depth minimized by taking advantage of prev count >= 4.
         $two_valid = | >>1$valid_count[m4_counter_width-1:2] || | $valid_count[2:1];
         // These are an optimization of the commented block below to operate on vectors, rather than bits.
         // TODO: Keep optimizing...
         {/entry[*]$$prev_entry_was_tail} = {/entry[*]>>1$reconstructed_is_tail\[m4_eval(m4_depth-2):0], /entry[m4_eval(m4_depth-1)]>>1$reconstructed_is_tail} /* circular << */;
         {/entry[*]$$push} = {m4_depth{$push}} & /entry[*]$prev_entry_was_tail;
         /entry[*]
            // Replaced with optimized versions above:
            // $prev_entry_was_tail = /entry[(entry+(m4_depth)-1)%(m4_depth)]>>1$reconstructed_is_tail;
            // $push = |m4_in_pipe$push && $prev_entry_was_tail;
            $valid = (>>1$reconstructed_valid && ! /m4_top|m4_out_pipe/entry>>m4_bypass_align$pop) || $push;
            $is_tail = |m4_in_pipe$trans_valid ? $prev_entry_was_tail  // shift tail
                                               : >>1$reconstructed_is_tail;  // retain tail
            $state = |m4_in_pipe$reset ? 1'b0
                                       : $valid && ! (|m4_in_pipe$two_valid && $is_tail);
      @m4_eval(m4_in_at + 1)
         $empty = ! $two_valid && ! $valid_count[0];
         $full = ($valid_count == full_mark_['']m4_plus_inst_id);  // Could optimize for power-of-two depth.
      /entry[*]
         @m4_eval(m4_in_at + 1)
            $prev_entry_state = /entry[(entry+(m4_depth)-1)%(m4_depth)]$state;
            $next_entry_state = /entry[(entry+1)%(m4_depth)]$state;
            $reconstructed_is_tail = (  /m4_top|m4_in_pipe$two_valid && (!$state && $prev_entry_state)) ||
                                     (! /m4_top|m4_in_pipe$two_valid && (!$next_entry_state && $state)) ||
                                     (|m4_in_pipe$empty && (entry == 0));  // need a tail when empty for push
            $is_head = $state && ! $prev_entry_state;
            $reconstructed_valid = $state || (/m4_top|m4_in_pipe$two_valid && $prev_entry_state);
   // Write data
   |m4_in_pipe
      @m4_in_at
         /entry[*]
            //?$push
            //   $aNY = |m4_in_pipe['']m4_trans_hier$ANY;
            m4_trans_hier
m4_trans_ind            $ANY = /entry$push ? /m4_top|m4_in_pipe['']m4_trans_hier$ANY : >>1$ANY /* RETAIN */;
   // Read data
   |m4_out_pipe
      @m4_out_at
         //$pop  = ! /m4_top|m4_in_pipe>>m4_align(m4_in_at + 1, m4_out_at)$empty && ! $blocked;
         /entry[*]
            $is_head = /m4_top|m4_in_pipe/entry>>m4_align(m4_in_at + 1, m4_out_at)$is_head;
            $pop  = $is_head && ! |m4_out_pipe$blocked;
            /read_masked
               m4_trans_hier
m4_trans_ind               $ANY = /entry$is_head ? /m4_top|m4_in_pipe/entry['']m4_trans_hier>>m4_align(m4_in_at + 1, m4_out_at)$ANY /* $aNY */ : '0;
            /accum
               m4_trans_hier
m4_trans_ind               $ANY = ((entry == 0) ? '0 : /entry[(entry+(m4_depth)-1)%(m4_depth)]/accum['']m4_trans_hier$ANY) |
                          /entry/read_masked['']m4_trans_hier$ANY;
         /head
            $trans_avail = |m4_out_pipe$trans_avail;
            ?$trans_avail
               m4_trans_hier
m4_trans_ind               $ANY = /m4_top|m4_out_pipe/entry[(m4_depth)-1]/accum['']m4_trans_hier$ANY;

   // Bypass
   |m4_out_pipe
      @m4_out_at
         // Available output.  Sometimes it's necessary to know what would be coming to determined
         // if it's blocked.  This can be used externally in that case.
         /fifo_head
            $trans_avail = |m4_out_pipe$trans_avail;
            ?$trans_avail
               m4_trans_hier
m4_trans_ind               $ANY = /m4_top|m4_in_pipe>>m4_reverse_bypass_align$would_bypass
m4_trans_ind                            ? /m4_top|m4_in_pipe['']m4_trans_hier>>m4_reverse_bypass_align$ANY
m4_trans_ind                            : |m4_out_pipe/head['']m4_trans_hier$ANY;
         $trans_avail = ! /m4_top|m4_in_pipe>>m4_reverse_bypass_align$would_bypass || /m4_top|m4_in_pipe>>m4_reverse_bypass_align$trans_avail;
         $trans_valid = $trans_avail && ! $blocked;
         ?$trans_valid
            m4_trans_hier
m4_trans_ind            $ANY = |m4_out_pipe/fifo_head['']m4_trans_hier$ANY;



   /* Alternate code for pointer indexing.  Replaces $ANY expression above.

   // Hierarchy
   |m4_in_pipe
      /entry2[(m4_depth)-1:0]

   // Head/Tail ptrs.
   |m4_in_pipe
      @m4_in_at
         >>1$WrPtr[m4_ptr_width-1:0] =
             $reset       ? '0 :
             $trans_valid ? ($WrPtr == (m4_depth - 1))
                              ? '0
                              : $WrPtr + {{(m4_ptr_width-1){1'b0}}, 1'b1} :
                            $RETAIN;
   |m4_out_pipe
      @m4_out_at
         >>1$RdPtr[m4_ptr_width-1:0] =
             /m4_top|m4_in_pipe>>m4_reverse_bypass_align$reset
                          ? '0 :
             $trans_valid ? ($RdPtr == (m4_depth - 1))
                              ? '0
                              : $RdPtr + {{(m4_ptr_width-1){1'b0}}, 1'b1} :
                            $RETAIN;
   // Write FIFO
   |m4_in_pipe
      @m4_in_at
         $dummy = '0;
         ?$trans_valid
            // This doesn't work because SV complains for FIFOs in replicated context that
            // there are multiple procedures that assign the signals.
            // Array writes can be done in an SV module.
            // The only long-term resolutions are support for module generation and use
            // signals declared within for loops with cross-hierarchy references in SV.
            // TODO: To make a simulation-efficient FIFO, use DesignWare.
            {/entry2[$WrPtr]$$ANY} = $ANY;
   // Read FIFO
   |m4_out_pipe
      @m4_out_at
         /read2
            $trans_valid = |m4_out_pipe$trans_valid;
            ?$trans_valid
               $ANY = /m4_top|m4_in_pipe/entry2[|m4_out_pipe$RdPtr]>>m4_reverse_bypass_align$ANY;
            `BOGUS_USE($dummy)
         ?$trans_valid
            $ANY = /read2$ANY;
   */
'],

['
m4_popdef(['m4_top'])
m4_popdef(['m4_in_pipe'])
m4_popdef(['m4_in_at'])
m4_popdef(['m4_out_pipe'])
m4_popdef(['m4_out_at'])
m4_popdef(['m4_depth'])
m4_popdef(['m4_trans_hier'])
m4_pushdef(['m4_high_water'])

m4_popdef(['m4_ptr_width'])
m4_popdef(['m4_counter_width'])
m4_popdef(['m4_bypass_align'])
m4_popdef(['m4_reverse_bypass_align'])
m4_popdef(['m4_trans_ind'])
'])


// A FIFO using simple_bypass_fifo.
// Requires include "simple_bypass_fifo.sv".
//
// The interface is identical to m4_flop_fifo, above, except that data width must be provided explicitly.
//
m4_define_plus(['m4_old_simple_bypass_fifo_v2'], ['
m4_pushdef(['m4_top'],       ['$5'])
m4_pushdef(['m4_in_pipe'],   ['$6'])
m4_pushdef(['m4_in_at'],     ['$7'])
m4_pushdef(['m4_out_pipe'],  ['$8'])
m4_pushdef(['m4_out_at'],    ['$9'])
m4_pushdef(['m4_depth'],     ['$10'])
m4_pushdef(['m4_width'],     ['$11'])
m4_pushdef(['m4_trans_hier'],['$12'])  // Eg: ['/flit'] or ['']
m4_pushdef(['m4_high_water'],['$13'])  // Default to 0.  Number of additional entries beyond full.

'], m4___file__, m4___line__, ['
   |m4_in_pipe
      @m4_in_at
         $out_blocked = /m4_top|m4_out_pipe>>m4_align(m4_out_at, m4_in_at)$blocked;
         $blocked = (/m4_top/fifo>>m4_align(0, m4_in_at)$cnt >= m4_eval(m4_depth - m4_ifelse(m4_high_water, [''], 0, ['m4_high_water']))) && $out_blocked;
   /fifo
      simple_bypass_fifo #(.WIDTH(m4_width), .DEPTH(m4_depth))
         fifo(.clk(clk), .reset(/m4_top|m4_in_pipe>>m4_align(m4_in_at, 0)$reset),
              .push(/m4_top|m4_in_pipe>>m4_align(m4_in_at, 0)$trans_valid),
              .data_in(/m4_top|m4_in_pipe['']m4_trans_hier>>m4_align(m4_in_at, 0)$ANY),
              .pop(/m4_top|m4_out_pipe>>m4_align(m4_out_at, 0)$trans_valid),
              .data_out(/m4_top|m4_out_pipe['']m4_trans_hier>>m4_align(m4_out_at, 0)$$ANY),
              .cnt($$cnt[2:0]));
   |m4_out_pipe
      @m4_out_at
         $trans_avail = /m4_top/fifo>>m4_align(0, m4_out_at)$cnt != 3'b0 || /m4_top|m4_in_pipe>>m4_align(m4_in_at, m4_out_at)$trans_avail;
         $trans_valid = $trans_avail && !$blocked;
'],

['
m4_popdef(['m4_top'])
m4_popdef(['m4_in_pipe'])
m4_popdef(['m4_in_at'])
m4_popdef(['m4_out_pipe'])
m4_popdef(['m4_out_at'])
m4_popdef(['m4_depth'])
m4_popdef(['m4_width'])
m4_popdef(['m4_trans_hier'])
m4_pushdef(['m4_high_water'])
'])


m4_nothing(['// A FIFO using simple_bypass_fifo.
// Requires include "simple_bypass_fifo.sv".
//
// The interface is identical to m4_flop_fifo, above, except that data width must be provided explicitly.
//
// Args:
//   /_top, |_in, @_in, |_out, @_out, #_depth, #_width: as one would expect.
//   /_trans: hierarchy for transaction, eg: ['/flit'] or ['']
//   #_high_water: Default to 0.  Number of additional entries beyond full.
'])m4_define_plus2(['simple_bypass_fifo_v2'], ['['
   $']['2
      $']['3
         $out_blocked = $']['1$']['4>>m4_align($']['5, $']['3)$blocked;
         $blocked = ($']['1/fifo>>m4_align(0, $']['3)$cnt >= m4_eval($']['6 - m4_ifelse($']['9, [''], 0, $']['9))) && $out_blocked;
   /fifo
      simple_bypass_fifo #(.WIDTH($']['7), .DEPTH($']['6))
         fifo(.clk(clk), .reset($']['1$']['2>>m4_align($']['3, 0)$reset),
              .push($']['1$']['2>>m4_align($']['3, 0)$trans_valid),
              .data_in($']['1$']['2$']['8>>m4_align($']['3, 0)$ANY),
              .pop($']['1$']['4>>m4_align($']['5, 0)$trans_valid),
              .data_out($']['1$']['4$']['8>>m4_align($']['5, 0)$$ANY),
              .cnt($$cnt[2:0]));
   $']['4
      $']['5
         $trans_avail = $']['1/fifo>>m4_align(0, $']['5)$cnt != 3'b0 || $']['1$']['2>>m4_align($']['3, $']['5)$trans_avail;
         $trans_valid = $trans_avail && !$blocked;']'], ['{/_top}'], ['{|_in}'], ['{@_in}'], ['{|_out}'], ['{@_out}'], ['{#_depth}'], ['{#_width}'], ['{/_trans}'], ['{#_high_water}'])m4_dnl
m4_nothing(['


'])\source m4_escaped_string(m4_FILE) 802['']m4_new_line()// A FIFO with virtual channels.
// VC copies of m4+flop_fifo, which drain based on a priority assigned to each VC.
// Data should arrive early in |in_pipe@in_stage, or in the stage prior.  It can be
// available on the output early in |out_pipe@out_stage or late the cycle before,
// determined by bypass_at.
// The FIFOs feed into a speculative pre-selected flit.  The
// pre-selected flit remains in the corresponding m4+flop_fifo until it is accepted
// externally, so the selection is non-blocking.  The pre-selected flit will be
// bumped by a higher-priority flit (but not an equal priority flit).
//
// Parameters begin as with m4_flop_fifo:
// m4+vc_flop_fifo_v2(top, in_pipe, in_at, out_pipe, out_at, depth, trans_hier, vc_range, prio_range [, bypass_at [, high_water]])

// Input interface:
//    |in_pipe
//       @in_stage  // (or cycle prior if bypass_stage requires it)
//          $reset         // A reset signal.
//          ?$trans_valid  // (| /vc[*]$vc_trans_valid)
//             $ANY        // Input transaction (under trans_hier if non-empty)
//    /vc[*]
//       |in_pipe
//          @in_stage
//             $vc_trans_valid
//       |out_pipe
//          @out_stage-1
//             $has_credit    // Credit is available for this VC (or by other means, it is okay to output this VC).
//             $Prio  // (config) the prio of each VC
// Output interface:
//   /vc[*]
//      |in_pipe
//         @in_stage
//            $blocked       // The corresponding input transaction, if valid, cannot be consumed
//                           // and must recirculate.
//      |out_pipe
//         @bypass_stage
//            $vc_trans_valid// An indication of the outbound $vc (or use /top|out_pipe$trans_valid &&
//                                                                        /top|out_pipe/trans_hier$vc).
//   |out_pipe
//      @bypass_stage
//         $trans_valid
//         ?$trans_valid
//            $ANY        // Output transaction (under trans_hier if given)

// Backpressure ($blocked, $full, $ValidCount) signals are per /vc; $trans_valid is a singleton
// for input and output and must consider per-VC backpressure; $trans_avail is not produced on
// output and should not be assigned externally for input.
//
m4_unsupported(['m4_vc_flop_fifo'], 1)
m4_define_plus(['m4_vc_flop_fifo_v2'], ['
m4_pushdef(['m4_top'],       ['$5'])
m4_pushdef(['m4_in_pipe'],   ['$6'])
m4_pushdef(['m4_in_at'],     ['$7'])
m4_pushdef(['m4_out_pipe'],  ['$8'])
m4_pushdef(['m4_out_at'],    ['$9'])
m4_pushdef(['m4_depth'],     ['$10'])
m4_pushdef(['m4_trans_hier'],['$11'])
m4_pushdef(['m4_vc_range'],  ['$12'])
m4_pushdef(['m4_prio_range'],['$13'])
m4_pushdef(['m4_bypass_at'], ['$14'])   // By default, m4_out_at, or can be the cycle before, in which case inputs and outputs are in the previous cycle.
m4_pushdef(['m4_high_water'],['$15'])

m4_define(['m4_bypass_at'], m4_ifelse(m4_bypass_at, [''], ['m4_out_at'], ['m4_bypass_at']))
m4_pushdef(['m4_arb_at'], m4_eval(m4_out_at - 1))  // Arb and read VC FIFOs the stage before m4_out_at.
m4_pushdef(['m4_bypass_align'], m4_align(m4_out_at, m4_in_at))
m4_pushdef(['m4_reverse_bypass_align'], m4_align(m4_in_at, m4_out_at))
m4_pushdef(['m4_trans_ind'], m4_ifelse(m4_trans_hier, [''], [''], ['   ']))

'], m4___file__, m4___line__, ['
   /vc[m4_vc_range]
      |m4_in_pipe
         @m4_in_at
            // Apply inputs to the right VC FIFO.
            //

            $reset = /m4_top|m4_in_pipe$reset;
            $trans_valid = $vc_trans_valid && ! /vc|m4_out_pipe>>m4_bypass_align$bypassed_fifos_for_this_vc;
            $trans_avail = $trans_valid;
            ?$trans_valid
               m4_trans_hier
m4_trans_ind               $ANY = /m4_top|m4_in_pipe['']m4_trans_hier$ANY;
      // Instantiate FIFO.  Output to stage (m4_out_at - 1) because bypass is m4_out_at.
      m4_flop_fifo_v2(['      $1'], ']m4___file__[', ']m4___line__[', ['m4_['']flop_fifo_v2(...)'], vc, m4_in_pipe, m4_in_at, m4_out_pipe, m4_arb_at, m4_depth, m4_trans_hier, m4_high_water)

   // FIFO select.
   //
   /vc[*]
      |m4_out_pipe
         @m4_arb_at
            $arbing = $trans_avail && $has_credit;
            /prio[m4_prio_range]
               // Decoded priority.
               >>1$Match = #prio == |m4_out_pipe$Prio;
            // Mask of same-prio VCs.
            /other_vc[m4_vc_range]
               >>1$SamePrio = |m4_out_pipe$Prio == /vc[#other_vc]|m4_out_pipe$Prio;
               // Select among same-prio VCs.
               $competing = $SamePrio && /vc[#other_vc]|m4_out_pipe$arbing;
            // Select FIFO if selected within priority and this VC has the selected (max available) priority.
            $fifo_sel = m4_am_max(/other_vc[*]$competing, vc) && | (/prio[*]$Match & /m4_top/prio[*]|m4_out_pipe$sel);
               // TODO: Need to replace m4_am_max with round-robin within priority.
            $blocked = ! $fifo_sel;
         @m4_bypass_at
            // Can bypass FIFOs?
            $can_bypass_fifos_for_this_vc = /vc|m4_in_pipe>>m4_reverse_bypass_align$vc_trans_valid &&
                                            /vc|m4_in_pipe>>m4_align(m4_eval(m4_in_at+1), m4_out_at)$empty &&
                                            $has_credit;

            // Indicate output VC as per-VC FIFO output $trans_valid or could bypass in this VC.
            $bypassed_fifos_for_this_vc = $can_bypass_fifos_for_this_vc && ! /m4_top|m4_out_pipe$fifo_trans_avail;
            $vc_trans_valid = $trans_valid || $bypassed_fifos_for_this_vc;
            `BOGUS_USE($vc_trans_valid)  // okay to not consume this
   /prio[m4_prio_range]
      |m4_out_pipe
         @m4_arb_at
            /vc[m4_vc_range]
               // Trans available for this prio/VC?
               $avail_within_prio = /m4_top/vc|m4_out_pipe$trans_avail &&
                                    /m4_top/vc|m4_out_pipe/prio$Match;
            // Is this priority available in FIFOs.
            $avail = | /vc[*]$avail_within_prio;
            // Select this priority if its the max available.
            $sel = m4_am_max(/prio[*]|m4_out_pipe$avail, prio);

   |m4_out_pipe
      @m4_arb_at
         $fifo_trans_avail = | /m4_top/vc[*]|m4_out_pipe$arbing;
         /fifos_out
            $fifo_trans_avail = |m4_out_pipe$fifo_trans_avail;
            /vc[m4_vc_range]
            m4_select(['            $1'], ']m4___file__[', ']m4___line__[', ['m4_['']select(...)'], $ANY, /m4_top, /vc, |m4_out_pipe['']m4_trans_hier, |m4_out_pipe, $fifo_sel, $ANY, $fifo_trans_avail)

         // Output transaction
         //

      @m4_bypass_at
         // Incorporate bypass
         // Bypass if there's no transaction from the FIFOs, and the incoming transaction is okay for output.
         $can_bypass_fifos = | /m4_top/vc[*]|m4_out_pipe$can_bypass_fifos_for_this_vc;
         $trans_valid = $fifo_trans_avail || $can_bypass_fifos;
         ?$trans_valid
            m4_trans_hier
m4_trans_ind            $ANY = |m4_out_pipe$fifo_trans_avail ? |m4_out_pipe/fifos_out$ANY : /m4_top|m4_in_pipe['']m4_trans_hier>>m4_reverse_bypass_align$ANY;
'],

['
m4_popdef(['m4_top'])
m4_popdef(['m4_in_pipe'])
m4_popdef(['m4_in_at'])
m4_popdef(['m4_out_pipe'])
m4_popdef(['m4_out_at'])
m4_popdef(['m4_depth'])
m4_popdef(['m4_trans_hier'])
m4_popdef(['m4_vc_range'])
m4_popdef(['m4_prio_range'])
m4_popdef(['m4_bypass_at'])
m4_popdef(['m4_high_water'])

m4_popdef(['m4_arb_at'])
m4_popdef(['m4_bypass_align'])
m4_popdef(['m4_reverse_bypass_align'])
m4_popdef(['m4_trans_ind'])
'])





m4_nothing(['// Flow from /_scope and /_top/no_bypass to /bypass#_cycles that provides a value that bypasses up-to #_cycles
// from previous stages of /_scope any contain a $_valid $_src_tag matching $_tag, or /_top/no_bypass$_value otherwise.
'])m4_define_plus2(['bypass'], ['['
   /bypass$']['2
      $ANY =
         // Bypass stages:
         m4_ifexpr($']['2 >= 1, ($']['3>>1$']['4 && ($']['3>>1$']['5 == $']['1$']['7)) ? $']['3>>1$']['6 :)
         m4_ifexpr($']['2 >= 2, ($']['3>>2$']['4 && ($']['3>>2$']['5 == $']['1$']['7)) ? $']['3>>2$']['6 :)
         m4_ifexpr($']['2 >= 3, ($']['3>>3$']['4 && ($']['3>>3$']['5 == $']['1$']['7)) ? $']['3>>3$']['6 :)
         $']['1/no_bypass$ANY;']'], ['{/_top}'], ['{#_cycles}'], ['{/_scope}'], ['{$_valid}'], ['{$_src_tag}'], ['{$_src_value}'], ['{$_tag}'])m4_dnl
m4_nothing(['




'])\source m4_escaped_string(m4_FILE) 977['']m4_new_line()// A simple ring.
//
// One transaction per cycle, which yields to the transaction on the ring.
//
// m4_simple_ring(hop, in_pipe, in_stage, out_pipe, out_stage, reset_scope, reset_stage, reset_sig)
//   hop:                   The name of the beh hier for a ring hop/stop.
//   [in/out]_[pipe/stage]: The pipeline name and stage of the input and output for the control logic
//                          in each hop.
//   reset_[scope/stage/sig]: The fully qualified reset signal and stage.
//
// Input interface:
//   /hop[*]
//      |in_pipe
//         @in_stage
//            $trans_avail   // A transaction is available for consumption.
//         @in_stage
//            ?trans_valid = $trans_avail && ! $blocked
//               $dest       // Destination hop
//         @(in_stage+1)
//            ?trans_valid
//               $ANY        // Input transaction
//   /hop[*]
//      |out_pipe
//         @out_stage
//            $blocked       // The corresponding output transaction, if valid, cannot be consumed
//                           // and will recirculate.
// Output interface:
//   /hop[*]
//      |in_pipe
//         @in_stage
//            $blocked       // The corresponding input transaction, if valid, cannot be consumed
//                           // and must recirculate.
//      |out_pipe
//         @out_stage
//            $trans_avail   // A transaction is available for consumption.
//         @(out_stage+1)
//            ?trans_valid = $trans_avail && ! $blocked
//               $ANY        // Output transaction


m4_define_plus(['m4_simple_ring'], ['

m4_pushdef(['m4_hop'],       ['$5'])
m4_pushdef(['m4_in_pipe'],   ['$6'])
m4_pushdef(['m4_in_at'],     ['$7'])
m4_pushdef(['m4_out_pipe'],  ['$8'])
m4_pushdef(['m4_out_at'],    ['$9'])
m4_pushdef(['m4_reset_scope'],['$10'])
m4_pushdef(['m4_reset_at'],  ['$11'])
m4_pushdef(['m4_reset_sig'], ['$12'])

m4_pushdef(['m4_out_in_align'], m4_align(m4_out_at, m4_in_at))
m4_pushdef(['m4_in_out_align'], m4_align(m4_in_at, m4_out_at))

'], m4___file__, m4___line__, ['

   // Logic
   /m4_hop[*]
      |default
         @0
            \SV_plus
               int prev_hop = (m4_hop + RING_STOPS - 1) % RING_STOPS;
      |m4_in_pipe
         @m4_in_at
            $blocked = /m4_hop|rg<>0$passed_on;
      |rg
         @m4_in_at
            $passed_on = /m4_hop[prev_hop]|rg>>1$pass_on;
            $valid = ! m4_reset_scope>>m4_align(m4_reset_at, m4_in_at)m4_reset_sig &&
                     ($passed_on || /m4_hop|m4_in_pipe<>0$trans_avail);
            $pass_on = $valid && ! /m4_hop|m4_out_pipe>>m4_out_in_align$trans_valid;
            $dest[RING_STOPS_WIDTH-1:0] =
               $passed_on
                  ? /m4_hop[prev_hop]|rg>>1$dest
                  : /m4_hop|m4_in_pipe<>0$dest;
         @m4_eval(m4_in_at + 1)
            ?$valid
               $ANY =
                  $passed_on
                     ? /m4_hop[prev_hop]|rg>>1$ANY
                     : /m4_hop|m4_in_pipe<>0$ANY;
      |m4_out_pipe
         // Ring out
         @m4_out_at
            $trans_avail = /m4_hop|rg>>m4_in_out_align$valid && (/m4_hop|rg>>m4_in_out_align$dest == m4_hop);
            $blocked = 1'b0;
            $trans_valid = $trans_avail && ! $blocked;
         ?$trans_valid
            @1
               $ANY = /m4_hop|rg>>m4_in_out_align$ANY;
'],

['
m4_popdef(['m4_hop'])
m4_popdef(['m4_in_pipe'])
m4_popdef(['m4_in_at'])
m4_popdef(['m4_out_pipe'])
m4_popdef(['m4_out_at'])
m4_popdef(['m4_reset_scope'])
m4_popdef(['m4_reset_at'])
m4_popdef(['m4_reset_sig'])

m4_popdef(['m4_out_in_align'])
m4_popdef(['m4_in_out_align'])
'])



// A one-cycle speculation flow.
// m4+1cyc_speculate(m4_top, m4_in_pipe, m4_out_pipe, m4_spec_stage, m4_comp_stage, m4_pred_sigs)
// Eg:
//    m4+1cyc_speculate(top, in_pipe, out_pipe, 0, 1, ['$taken, $target'])
// Inputs:
//    |m4_in_pipe
//       @m4_pred_stage (or earlier)
//          /trans
//             $result1   // Correct result(s)
//             $result2
//          /pred_trans
//             $result1   // Predicted result(s)
// Outputs:
//    |m4_out_pipe
//       /trans
//          @m4_spec_stage
//             $result1
//             $result2
//          @m4_comp_stage
//             $valid
//

m4_define_plus(['m4_1cyc_speculate'], ['
m4_pushdef(['m4_top'],       ['$5'])
m4_pushdef(['m4_in_pipe'],   ['$6'])
m4_pushdef(['m4_out_pipe'],  ['$7'])
m4_pushdef(['m4_spec_stage'],['$8'])  // Stage in which speculation is done.
m4_pushdef(['m4_comp_stage'],['$9'])  // Stage in which comparison is performed.
m4_pushdef(['m4_pred_sigs'], ['$10']) // Comma-separated list of predicted signals.

'], m4___file__, m4___line__, ['
   |m4_in_pipe
      ?$valid
         @m4_spec_stage
            /trans  // Context for non-speculative calculation.
            /pred_trans  // Context for prediction (speculative transaction).
               $ANY = |m4_in_pipe/trans$ANY;  // Pass through real calculation by default.
         @m4_comp_stage
            /comp
               // Pull speculative signals and actual ones for comparison to
               // determine mispredict.
               $ANY = |m4_in_pipe/trans$ANY ^ |m4_in_pipe/pred_trans$ANY;
               $mispred = | {m4_pred_sigs};
      @m4_comp_stage
         // Unconditioned signal indicating need to delay 1 cycle.
         $delay = $valid && (
                       /comp$mispred ||  // misprediction
                       >>1$delay         // previous was delayed
                    );
   |m4_out_pipe
      /trans
         @m4_spec_stage
            // Context for transaction post-speculation, timed to correct speculation.
            $delayed = /m4_top|m4_in_pipe>>1$delay;
            // Use $maybe_valid as a condition if there isn't time to use $valid.
            $maybe_valid = /m4_top|m4_in_pipe<>0$valid || $delayed;
            ?$maybe_valid
               $ANY = $delayed ? /m4_top|m4_in_pipe/trans>>1$ANY : /m4_top|m4_in_pipe/pred_trans<>0$ANY;
         @m4_comp_stage
            $valid = (/m4_top|m4_in_pipe<>0$valid && ! /m4_top|m4_in_pipe/comp<>0$mispred) || $delayed;
'],

['
m4_popdef(['m4_top'])
m4_popdef(['m4_in_pipe'])
m4_popdef(['m4_out_pipe'])
m4_popdef(['m4_comp_stage'])
m4_popdef(['m4_pred_sigs'])
'])



'])m4_dnl
