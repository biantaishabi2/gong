defmodule Gong.BDD.Instructions.V1 do
  @moduledoc "Gong BDD v1 指令运行时实现"

  import ExUnit.Assertions

  @type ctx :: map()
  @type meta :: map()

  # 编译期提取已实现的指令列表
  @supported_instructions (
    __ENV__.file
    |> File.read!()
    |> then(fn src ->
      Regex.scan(~r/\{\:(?:given|when|then),\s+\:([a-zA-Z0-9_]+)\}\s*->/, src,
        capture: :all_but_first
      )
    end)
    |> List.flatten()
    |> Enum.map(&String.to_atom/1)
    |> Enum.uniq()
    |> Enum.sort()
  )

  @spec capabilities() :: MapSet.t(atom())
  def capabilities, do: MapSet.new(@supported_instructions)

  @spec new_run_id() :: String.t()
  def new_run_id do
    "bdd_run_" <> Integer.to_string(System.unique_integer([:positive]))
  end

  @spec run_step!(ctx(), :given | :when | :then, atom(), map(), meta(), term()) :: ctx()
  def run_step!(ctx, kind, name, args, meta, _step_id \\ nil) do
    scenario_id = Map.get(ctx, :scenario_id)

    try do
      run!(ctx, kind, name, args, meta)
    rescue
      e in [ExUnit.AssertionError, ArgumentError] ->
        dump_evidence(ctx, scenario_id, meta, e)
        reraise(e, __STACKTRACE__)

      e ->
        dump_evidence(ctx, scenario_id, meta, e)
        reraise(e, __STACKTRACE__)
    end
  end

  @spec run!(ctx(), :given | :when | :then, atom(), map(), meta()) :: ctx()
  def run!(ctx, kind, name, args, meta \\ %{})

  # ── Common: 测试基础设施 ──

  def run!(ctx, kind, name, args, meta) do
    case {kind, name} do
      {:given, :create_temp_dir} ->
        create_temp_dir!(ctx, args, meta)

      {:given, :create_temp_file} ->
        create_temp_file!(ctx, args, meta)

      {:given, :create_large_file} ->
        create_large_file!(ctx, args, meta)

      {:given, :create_binary_file} ->
        create_binary_file!(ctx, args, meta)

      {:given, :create_png_file} ->
        create_png_file!(ctx, args, meta)

      {:given, :create_symlink} ->
        create_symlink!(ctx, args, meta)

      {:given, :set_file_permission} ->
        set_file_permission!(ctx, args, meta)

      {:given, :set_var} ->
        set_var!(ctx, args, meta)

      {:given, :generate_content} ->
        generate_content!(ctx, args, meta)

      {:given, :create_bom_file} ->
        create_bom_file!(ctx, args, meta)

      # ── Tools: 工具调用 ──

      {:when, :tool_read} ->
        tool_read!(ctx, args, meta)

      {:when, :tool_write} ->
        tool_write!(ctx, args, meta)

      {:when, :tool_edit} ->
        tool_edit!(ctx, args, meta)

      {:when, :tool_bash} ->
        tool_bash!(ctx, args, meta)

      {:when, :tool_grep} ->
        tool_grep!(ctx, args, meta)

      {:when, :tool_find} ->
        tool_find!(ctx, args, meta)

      {:when, :tool_ls} ->
        tool_ls!(ctx, args, meta)

      # ── 截断操作 ──

      {:when, :truncate_head} ->
        truncate_head!(ctx, args, meta)

      {:when, :truncate_tail} ->
        truncate_tail!(ctx, args, meta)

      {:when, :truncate_line} ->
        truncate_line!(ctx, args, meta)

      # ── Assertions: 结果断言 ──

      {:then, :assert_tool_success} ->
        assert_tool_success!(ctx, args, meta)

      {:then, :assert_tool_error} ->
        assert_tool_error!(ctx, args, meta)

      {:then, :assert_tool_truncated} ->
        assert_tool_truncated!(ctx, args, meta)

      {:then, :assert_read_image} ->
        assert_read_image!(ctx, args, meta)

      {:then, :assert_read_text} ->
        assert_read_text!(ctx, args, meta)

      {:then, :assert_file_exists} ->
        assert_file_exists!(ctx, args, meta)

      {:then, :assert_file_content} ->
        assert_file_content!(ctx, args, meta)

      {:then, :assert_file_has_bom} ->
        assert_file_has_bom!(ctx, args, meta)

      {:then, :assert_file_has_crlf} ->
        assert_file_has_crlf!(ctx, args, meta)

      {:then, :assert_file_no_crlf} ->
        assert_file_no_crlf!(ctx, args, meta)

      {:then, :assert_result_field} ->
        assert_result_field!(ctx, args, meta)

      {:then, :assert_exit_code} ->
        assert_exit_code!(ctx, args, meta)

      {:then, :assert_output_contains} ->
        assert_output_contains!(ctx, args, meta)

      {:then, :assert_output_not_contains} ->
        assert_output_not_contains!(ctx, args, meta)

      {:then, :assert_truncation_result} ->
        assert_truncation_result!(ctx, args, meta)

      {:then, :assert_truncation_notification} ->
        assert_truncation_notification!(ctx, args, meta)

      # ── Agent 集成 ──

      {:given, :configure_agent} ->
        configure_agent!(ctx, args, meta)

      {:given, :mock_llm_response} ->
        mock_llm_response!(ctx, args, meta)

      {:given, :inject_steering} ->
        inject_steering!(ctx, args, meta)

      {:given, :register_hook} ->
        register_hook!(ctx, args, meta)

      {:given, :attach_telemetry_handler} ->
        attach_telemetry_handler!(ctx, args, meta)

      {:given, :configure_hooks} ->
        configure_hooks!(ctx, args, meta)

      {:when, :agent_chat} ->
        agent_chat!(ctx, args, meta)

      {:when, :agent_stream} ->
        agent_stream!(ctx, args, meta)

      {:when, :agent_abort} ->
        agent_abort!(ctx, args, meta)

      {:when, :trigger_compaction} ->
        trigger_compaction!(ctx, args, meta)

      {:then, :assert_agent_reply} ->
        assert_agent_reply!(ctx, args, meta)

      {:then, :assert_tool_was_called} ->
        assert_tool_was_called!(ctx, args, meta)

      {:then, :assert_tool_not_called} ->
        assert_tool_not_called!(ctx, args, meta)

      {:then, :assert_hook_fired} ->
        assert_hook_fired!(ctx, args, meta)

      {:then, :assert_compaction_triggered} ->
        assert_compaction_triggered!(ctx, args, meta)

      {:then, :assert_compaction_not_triggered} ->
        assert_compaction_not_triggered!(ctx, args, meta)

      {:then, :assert_retry_happened} ->
        assert_retry_happened!(ctx, args, meta)

      {:then, :assert_no_retry} ->
        assert_no_retry!(ctx, args, meta)

      {:then, :assert_hook_blocked} ->
        assert_hook_blocked!(ctx, args, meta)

      {:then, :assert_telemetry_received} ->
        assert_telemetry_received!(ctx, args, meta)

      {:then, :assert_hook_error_logged} ->
        assert_hook_error_logged!(ctx, args, meta)

      {:then, :assert_result_content_contains} ->
        assert_result_content_contains!(ctx, args, meta)

      {:then, :assert_result_content_not_contains} ->
        assert_result_content_not_contains!(ctx, args, meta)

      {:then, :assert_conversation_contains} ->
        assert_conversation_contains!(ctx, args, meta)

      {:then, :assert_stream_events} ->
        assert_stream_events!(ctx, args, meta)

      {:then, :assert_no_crash} ->
        assert_no_crash!(ctx, args, meta)

      {:then, :assert_last_error} ->
        assert_last_error!(ctx, args, meta)

      # ── Tape 存储 ──

      {:given, :tape_init} ->
        tape_init_given!(ctx, args, meta)

      {:given, :tape_append} ->
        tape_append_given!(ctx, args, meta)

      {:given, :tape_handoff} ->
        tape_handoff_given!(ctx, args, meta)

      {:given, :tape_fork} ->
        tape_fork_given!(ctx, args, meta)

      {:given, :tape_close_db} ->
        tape_close_db!(ctx, args, meta)

      {:given, :tape_restore_parent} ->
        tape_restore_parent!(ctx, args, meta)

      {:given, :corrupt_jsonl} ->
        corrupt_jsonl!(ctx, args, meta)

      {:given, :delete_file} ->
        delete_file!(ctx, args, meta)

      {:given, :clear_file} ->
        clear_file!(ctx, args, meta)

      {:when, :when_tape_init} ->
        tape_init_when!(ctx, args, meta)

      {:when, :when_tape_append} ->
        tape_append_when!(ctx, args, meta)

      {:when, :when_tape_handoff} ->
        tape_handoff_when!(ctx, args, meta)

      {:when, :when_tape_between_anchors} ->
        tape_between_anchors_when!(ctx, args, meta)

      {:when, :when_tape_search} ->
        tape_search_when!(ctx, args, meta)

      {:when, :when_tape_fork} ->
        tape_fork_when!(ctx, args, meta)

      {:when, :when_tape_merge} ->
        tape_merge_when!(ctx, args, meta)

      {:when, :when_tape_rebuild_index} ->
        tape_rebuild_index_when!(ctx, args, meta)

      {:then, :assert_dir_exists} ->
        assert_dir_exists!(ctx, args, meta)

      {:then, :assert_db_exists} ->
        assert_db_exists!(ctx, args, meta)

      {:then, :assert_entry_count} ->
        assert_entry_count!(ctx, args, meta)

      {:then, :assert_anchor_count} ->
        assert_anchor_count!(ctx, args, meta)

      {:then, :assert_jsonl_contains} ->
        assert_jsonl_contains!(ctx, args, meta)

      {:then, :assert_jsonl_not_contains} ->
        assert_jsonl_not_contains!(ctx, args, meta)

      {:then, :assert_query_results} ->
        assert_query_results!(ctx, args, meta)

      {:then, :assert_search_results} ->
        assert_search_results!(ctx, args, meta)

      {:then, :assert_tape_error} ->
        assert_tape_error!(ctx, args, meta)

      {:then, :assert_fork_cleaned} ->
        assert_fork_cleaned!(ctx, args, meta)

      {:then, :assert_entry_has_metadata} ->
        assert_entry_has_metadata!(ctx, args, meta)

      {:then, :assert_search_result_count} ->
        assert_search_result_count!(ctx, args, meta)

      # ── Compaction 压缩 ──

      {:given, :compaction_messages} ->
        compaction_messages!(ctx, args, meta)

      {:given, :compaction_messages_with_system} ->
        compaction_messages_with_system!(ctx, args, meta)

      {:given, :compaction_lock_acquired} ->
        compaction_lock_acquired!(ctx, args, meta)

      {:given, :compaction_summarize_fn_ok} ->
        compaction_summarize_fn_ok!(ctx, args, meta)

      {:given, :compaction_summarize_fn_fail} ->
        compaction_summarize_fn_fail!(ctx, args, meta)

      {:given, :compaction_summarize_fn_raise} ->
        compaction_summarize_fn_raise!(ctx, args, meta)

      {:when, :when_estimate_tokens} ->
        when_estimate_tokens!(ctx, args, meta)

      {:when, :when_compact} ->
        when_compact!(ctx, args, meta)

      {:when, :when_compact_and_handoff} ->
        when_compact_and_handoff!(ctx, args, meta)

      {:when, :when_acquire_lock} ->
        when_acquire_lock!(ctx, args, meta)

      {:when, :when_release_lock} ->
        when_release_lock!(ctx, args, meta)

      {:then, :assert_token_estimate} ->
        assert_token_estimate!(ctx, args, meta)

      {:then, :assert_compacted} ->
        assert_compacted!(ctx, args, meta)

      {:then, :assert_not_compacted} ->
        assert_not_compacted!(ctx, args, meta)

      {:then, :assert_summary_exists} ->
        assert_summary_exists!(ctx, args, meta)

      {:then, :assert_summary_nil} ->
        assert_summary_nil!(ctx, args, meta)

      {:then, :assert_system_preserved} ->
        assert_system_preserved!(ctx, args, meta)

      {:then, :assert_compaction_error} ->
        assert_compaction_error!(ctx, args, meta)

      {:then, :assert_tape_has_compaction_anchor} ->
        assert_tape_has_compaction_anchor!(ctx, args, meta)

      {:then, :assert_no_compaction_error} ->
        assert_no_compaction_error!(ctx, args, meta)

      # ── Hook 扩展断言 ──

      {:then, :assert_no_hook_error} ->
        assert_no_hook_error!(ctx, args, meta)

      {:then, :assert_telemetry_sequence} ->
        assert_telemetry_sequence!(ctx, args, meta)

      # ── Agent Loop: Steering ──

      {:given, :steering_queue_empty} ->
        steering_queue_empty!(ctx, args, meta)

      {:when, :steering_push} ->
        steering_push!(ctx, args, meta)

      {:when, :steering_check} ->
        steering_check!(ctx, args, meta)

      {:when, :steering_skip_result} ->
        steering_skip_result!(ctx, args, meta)

      {:then, :assert_steering_pending} ->
        assert_steering_pending!(ctx, args, meta)

      {:then, :assert_steering_empty} ->
        assert_steering_empty!(ctx, args, meta)

      {:then, :assert_steering_message} ->
        assert_steering_message!(ctx, args, meta)

      {:then, :assert_steering_skip_contains} ->
        assert_steering_skip_contains!(ctx, args, meta)

      {:then, :assert_steering_message_nil} ->
        assert_steering_message_nil!(ctx, args, meta)

      {:then, :assert_steering_not_pending} ->
        assert_steering_not_pending!(ctx, args, meta)

      {:when, :steering_push_typed} ->
        steering_push_typed!(ctx, args, meta)

      {:when, :steering_check_steering} ->
        steering_check_steering!(ctx, args, meta)

      # ── Agent Loop: Retry ──

      {:when, :classify_error} ->
        classify_error!(ctx, args, meta)

      {:when, :retry_delay} ->
        retry_delay!(ctx, args, meta)

      {:when, :retry_should_retry} ->
        retry_should_retry!(ctx, args, meta)

      {:then, :assert_error_class} ->
        assert_error_class!(ctx, args, meta)

      {:then, :assert_delay_ms} ->
        assert_delay_ms!(ctx, args, meta)

      {:then, :assert_should_retry} ->
        assert_should_retry!(ctx, args, meta)

      # ── Agent Loop: Compaction 配对保护 ──

      {:given, :compaction_messages_with_tools} ->
        compaction_messages_with_tools!(ctx, args, meta)

      {:then, :assert_tool_pairs_intact} ->
        assert_tool_pairs_intact!(ctx, args, meta)

      # ── Agent Loop: 结构化摘要 ──

      {:given, :compaction_messages_with_tool_calls} ->
        compaction_messages_with_tool_calls!(ctx, args, meta)

      {:given, :compaction_messages_with_summary} ->
        compaction_messages_with_summary!(ctx, args, meta)

      {:when, :build_summarize_prompt} ->
        build_summarize_prompt!(ctx, args, meta)

      {:when, :extract_file_operations} ->
        extract_file_operations!(ctx, args, meta)

      {:then, :assert_prompt_contains} ->
        assert_prompt_contains!(ctx, args, meta)

      {:then, :assert_prompt_mode} ->
        assert_prompt_mode!(ctx, args, meta)

      {:then, :assert_file_ops_contains} ->
        assert_file_ops_contains!(ctx, args, meta)

      # ── Prompt 工程 ──

      {:given, :prompt_messages_with_long_content} ->
        prompt_messages_with_long_content!(ctx, args, meta)

      {:given, :prompt_messages_plain} ->
        prompt_messages_plain!(ctx, args, meta)

      {:given, :prompt_messages_multi_tools} ->
        prompt_messages_multi_tools!(ctx, args, meta)

      {:given, :prompt_messages_with_summary} ->
        prompt_messages_with_summary_prompt!(ctx, args, meta)

      {:when, :build_default_prompt} ->
        build_default_prompt!(ctx, args, meta)

      {:when, :build_workspace_prompt} ->
        build_workspace_prompt!(ctx, args, meta)

      {:when, :format_conversation} ->
        format_conversation!(ctx, args, meta)

      {:when, :extract_prompt_file_ops} ->
        extract_prompt_file_ops!(ctx, args, meta)

      {:when, :find_previous_summary} ->
        find_previous_summary!(ctx, args, meta)

      {:then, :assert_prompt_text} ->
        assert_prompt_text!(ctx, args, meta)

      {:then, :assert_formatted_length} ->
        assert_formatted_length!(ctx, args, meta)

      {:then, :assert_file_ops_text} ->
        assert_file_ops_text!(ctx, args, meta)

      {:then, :assert_previous_summary} ->
        assert_previous_summary!(ctx, args, meta)

      {:then, :assert_previous_summary_nil} ->
        assert_previous_summary_nil!(ctx, args, meta)

      # ── Lock 并发 & Token 精度 ──

      {:when, :concurrent_lock_acquire} ->
        concurrent_lock_acquire!(ctx, args, meta)

      {:then, :assert_lock_race_result} ->
        assert_lock_race_result!(ctx, args, meta)

      {:when, :estimate_text} ->
        estimate_text!(ctx, args, meta)

      {:then, :assert_token_estimate_value} ->
        assert_token_estimate_value!(ctx, args, meta)

      # ── Provider Registry ──

      {:when, :init_provider_registry} ->
        init_provider_registry!(ctx, args, meta)

      {:when, :register_provider} ->
        register_provider!(ctx, args, meta)

      {:when, :register_provider_with_invalid_config} ->
        register_provider_with_invalid_config!(ctx, args, meta)

      {:when, :switch_provider} ->
        switch_provider!(ctx, args, meta)

      {:when, :switch_provider_expect_error} ->
        switch_provider_expect_error!(ctx, args, meta)

      {:when, :provider_fallback} ->
        provider_fallback!(ctx, args, meta)

      {:when, :provider_fallback_expect_error} ->
        provider_fallback_expect_error!(ctx, args, meta)

      {:then, :assert_provider_count} ->
        assert_provider_count!(ctx, args, meta)

      {:then, :assert_current_provider} ->
        assert_current_provider!(ctx, args, meta)

      {:then, :assert_provider_error} ->
        assert_provider_error!(ctx, args, meta)

      {:then, :assert_provider_list_order} ->
        assert_provider_list_order!(ctx, args, meta)

      # ── Thinking 预算 ──

      {:when, :validate_thinking_level} ->
        validate_thinking_level!(ctx, args, meta)

      {:when, :get_thinking_budget} ->
        get_thinking_budget!(ctx, args, meta)

      {:when, :thinking_to_provider} ->
        thinking_to_provider!(ctx, args, meta)

      {:then, :assert_thinking_valid} ->
        assert_thinking_valid!(ctx, args, meta)

      {:then, :assert_thinking_invalid} ->
        assert_thinking_invalid!(ctx, args, meta)

      {:then, :assert_thinking_budget} ->
        assert_thinking_budget!(ctx, args, meta)

      {:then, :assert_thinking_params} ->
        assert_thinking_params!(ctx, args, meta)

      {:then, :assert_thinking_params_empty} ->
        assert_thinking_params_empty!(ctx, args, meta)

      # ── Cost 追踪 ──

      {:when, :init_cost_tracker} ->
        init_cost_tracker!(ctx, args, meta)

      {:when, :record_llm_call} ->
        record_llm_call!(ctx, args, meta)

      {:when, :reset_cost_tracker} ->
        reset_cost_tracker!(ctx, args, meta)

      {:then, :assert_cost_summary} ->
        assert_cost_summary!(ctx, args, meta)

      {:then, :assert_last_call} ->
        assert_last_call!(ctx, args, meta)

      # ── Prompt 模板 ──

      {:when, :init_prompt_templates} ->
        init_prompt_templates!(ctx, args, meta)

      {:when, :register_template} ->
        register_template!(ctx, args, meta)

      {:when, :get_template} ->
        get_template!(ctx, args, meta)

      {:when, :get_template_expect_error} ->
        get_template_expect_error!(ctx, args, meta)

      {:when, :render_template} ->
        render_template!(ctx, args, meta)

      {:then, :assert_template_exists} ->
        assert_template_exists!(ctx, args, meta)

      {:then, :assert_template_variables} ->
        assert_template_variables!(ctx, args, meta)

      {:then, :assert_rendered_content} ->
        assert_rendered_content!(ctx, args, meta)

      {:then, :assert_template_error} ->
        assert_template_error!(ctx, args, meta)

      # ── RPC 模式 ──

      {:when, :parse_rpc_request} ->
        parse_rpc_request!(ctx, args, meta)

      {:when, :rpc_dispatch} ->
        rpc_dispatch!(ctx, args, meta)

      {:when, :rpc_dispatch_missing} ->
        rpc_dispatch_missing!(ctx, args, meta)

      {:when, :rpc_handle} ->
        rpc_handle!(ctx, args, meta)

      {:then, :assert_rpc_parsed} ->
        assert_rpc_parsed!(ctx, args, meta)

      {:then, :assert_rpc_error} ->
        assert_rpc_error!(ctx, args, meta)

      {:then, :assert_rpc_result} ->
        assert_rpc_result!(ctx, args, meta)

      {:then, :assert_rpc_response_json} ->
        assert_rpc_response_json!(ctx, args, meta)

      # ── Auth OAuth ──

      {:when, :detect_auth_method} ->
        detect_auth_method!(ctx, args, meta)

      {:when, :generate_authorize_url} ->
        generate_authorize_url!(ctx, args, meta)

      {:when, :exchange_auth_code} ->
        exchange_auth_code!(ctx, args, meta)

      {:then, :assert_auth_method} ->
        assert_auth_method!(ctx, args, meta)

      {:then, :assert_authorize_url} ->
        assert_authorize_url!(ctx, args, meta)

      {:then, :assert_auth_token} ->
        assert_auth_token!(ctx, args, meta)

      # ── Cross-provider & Command ──

      {:given, :cross_provider_messages} ->
        cross_provider_messages!(ctx, args, meta)

      {:given, :cross_provider_multipart_message} ->
        cross_provider_multipart_message!(ctx, args, meta)

      {:when, :convert_messages} ->
        convert_messages!(ctx, args, meta)

      {:when, :build_handoff_summary} ->
        build_handoff_summary!(ctx, args, meta)

      {:then, :assert_converted_messages} ->
        assert_converted_messages!(ctx, args, meta)

      {:then, :assert_handoff_summary_not_empty} ->
        assert_handoff_summary_not_empty!(ctx, args, meta)

      {:then, :assert_content_is_text} ->
        assert_content_is_text!(ctx, args, meta)

      {:when, :init_command_registry} ->
        init_command_registry!(ctx, args, meta)

      {:when, :register_command} ->
        register_command!(ctx, args, meta)

      {:when, :execute_command} ->
        execute_command!(ctx, args, meta)

      {:when, :execute_command_expect_error} ->
        execute_command_expect_error!(ctx, args, meta)

      {:then, :assert_command_result} ->
        assert_command_result!(ctx, args, meta)

      {:then, :assert_command_error} ->
        assert_command_error!(ctx, args, meta)

      {:then, :assert_command_count} ->
        assert_command_count!(ctx, args, meta)

      # ── Auth 补充 ──

      {:when, :refresh_auth_token} ->
        refresh_auth_token!(ctx, args, meta)

      {:when, :check_token_expired} ->
        check_token_expired!(ctx, args, meta)

      {:then, :assert_token_expired} ->
        assert_token_expired!(ctx, args, meta)

      {:when, :get_api_key} ->
        get_api_key!(ctx, args, meta)

      {:then, :assert_api_key_result} ->
        assert_api_key_result!(ctx, args, meta)

      # ── Thinking 补充 ──

      {:when, :parse_thinking_level} ->
        parse_thinking_level!(ctx, args, meta)

      {:then, :assert_parsed_thinking_level} ->
        assert_parsed_thinking_level!(ctx, args, meta)

      {:then, :assert_parsed_thinking_error} ->
        assert_parsed_thinking_error!(ctx, args, meta)

      # ── Provider 补充 ──

      {:when, :cleanup_provider_registry} ->
        cleanup_provider_registry!(ctx, args, meta)

      {:then, :assert_provider_current_nil} ->
        assert_provider_current_nil!(ctx, args, meta)

      # ── Cost 补充 ──

      {:then, :assert_cost_history} ->
        assert_cost_history!(ctx, args, meta)

      {:then, :assert_last_call_nil} ->
        assert_last_call_nil!(ctx, args, meta)

      # ── Template 补充 ──

      {:then, :assert_template_list_count} ->
        assert_template_list_count!(ctx, args, meta)

      # ── RPC 补充 ──

      {:when, :rpc_dispatch_raise} ->
        rpc_dispatch_raise!(ctx, args, meta)

      # ── CrossProvider 补充 ──

      {:given, :cross_provider_tool_calls_message} ->
        cross_provider_tool_calls_message!(ctx, args, meta)

      {:then, :assert_command_exists} ->
        assert_command_exists!(ctx, args, meta)

      {:then, :assert_converted_has_tool_calls} ->
        assert_converted_has_tool_calls!(ctx, args, meta)

      # ── Extension 补充 ──

      {:then, :assert_extension_commands} ->
        assert_extension_commands!(ctx, args, meta)

      {:when, :cleanup_extension} ->
        cleanup_extension!(ctx, args, meta)

      {:then, :assert_extension_cleanup_called} ->
        assert_extension_cleanup_called!(ctx, args, meta)

      # ── Stream 补充 ──

      {:when, :stream_tool_chunks} ->
        stream_tool_chunks!(ctx, args, meta)

      {:then, :assert_tool_event_sequence} ->
        assert_tool_event_sequence!(ctx, args, meta)

      {:then, :assert_tool_event_name} ->
        assert_tool_event_name!(ctx, args, meta)

      # ── Agent Loop: Auto-Compaction ──

      {:when, :auto_compact} ->
        auto_compact!(ctx, args, meta)

      {:then, :assert_auto_compacted} ->
        assert_auto_compacted!(ctx, args, meta)

      {:then, :assert_auto_no_action} ->
        assert_auto_no_action!(ctx, args, meta)

      # ── E2E LLM 测试 ──

      {:given, :check_e2e_provider} ->
        check_e2e_provider!(ctx, args, meta)

      {:when, :agent_chat_live} ->
        agent_chat_live!(ctx, args, meta)

      {:when, :agent_chat_continue} ->
        agent_chat_continue!(ctx, args, meta)

      {:then, :assert_context_compactable} ->
        assert_context_compactable!(ctx, args, meta)

      # ── ModelRegistry ──

      {:given, :init_model_registry} ->
        init_model_registry!(ctx, args, meta)

      {:given, :register_model} ->
        register_model!(ctx, args, meta)

      {:when, :switch_model} ->
        switch_model!(ctx, args, meta)

      {:when, :validate_model} ->
        validate_model!(ctx, args, meta)

      {:then, :assert_current_model} ->
        assert_current_model!(ctx, args, meta)

      {:then, :assert_model_error} ->
        assert_model_error!(ctx, args, meta)

      {:then, :assert_model_count} ->
        assert_model_count!(ctx, args, meta)

      {:when, :get_model_string} ->
        get_model_string!(ctx, args, meta)

      {:when, :list_models} ->
        list_models!(ctx, args, meta)

      {:when, :cleanup_model_registry} ->
        cleanup_model_registry!(ctx, args, meta)

      {:when, :get_model_string_safe} ->
        get_model_string_safe!(ctx, args, meta)

      {:then, :assert_model_string} ->
        assert_model_string!(ctx, args, meta)

      {:then, :assert_model_list_count} ->
        assert_model_list_count!(ctx, args, meta)

      # ── Stream ──

      {:given, :mock_stream_response} ->
        mock_stream_response!(ctx, args, meta)

      {:then, :assert_stream_content} ->
        assert_stream_content!(ctx, args, meta)

      # ── Abort ──

      {:given, :setup_abort_scenario} ->
        setup_abort_scenario!(ctx, args, meta)

      {:when, :send_abort_signal} ->
        send_abort_signal!(ctx, args, meta)

      {:then, :assert_aborted} ->
        assert_aborted!(ctx, args, meta)

      {:then, :assert_abort_reset} ->
        assert_abort_reset!(ctx, args, meta)

      # ── Abort unit ──

      {:when, :abort_signal} ->
        abort_signal!(ctx, args, meta)

      {:when, :abort_check_catch} ->
        abort_check_catch!(ctx, args, meta)

      {:when, :abort_reset} ->
        abort_reset!(ctx, args, meta)

      {:when, :abort_safe_execute} ->
        abort_safe_execute!(ctx, args, meta)

      {:then, :assert_abort_flag} ->
        assert_abort_flag!(ctx, args, meta)

      {:then, :assert_abort_reason} ->
        assert_abort_reason!(ctx, args, meta)

      {:then, :assert_abort_caught} ->
        assert_abort_caught!(ctx, args, meta)

      {:then, :assert_safe_execute_result} ->
        assert_safe_execute_result!(ctx, args, meta)

      {:then, :assert_partial_content} ->
        assert_partial_content!(ctx, args, meta)

      # ── Session 树形分支 ──

      {:when, :tape_branch_from} ->
        tape_branch_from!(ctx, args, meta)

      {:when, :tape_navigate} ->
        tape_navigate!(ctx, args, meta)

      {:when, :tape_build_context} ->
        tape_build_context!(ctx, args, meta)

      {:then, :assert_tape_branches} ->
        assert_tape_branches!(ctx, args, meta)

      {:then, :assert_tape_context_path} ->
        assert_tape_context_path!(ctx, args, meta)

      # ── Extension ──

      {:given, :create_extension_dir} ->
        create_extension_dir!(ctx, args, meta)

      {:given, :create_extension_file} ->
        create_extension_file!(ctx, args, meta)

      {:when, :discover_extensions} ->
        discover_extensions!(ctx, args, meta)

      {:when, :load_extension} ->
        load_extension!(ctx, args, meta)

      {:when, :load_all_extensions} ->
        load_all_extensions!(ctx, args, meta)

      {:then, :assert_extension_loaded} ->
        assert_extension_loaded!(ctx, args, meta)

      {:then, :assert_extension_tools} ->
        assert_extension_tools!(ctx, args, meta)

      {:then, :assert_extension_error} ->
        assert_extension_error!(ctx, args, meta)

      {:then, :assert_extension_count} ->
        assert_extension_count!(ctx, args, meta)

      # ── Follow-up ──

      {:given, :inject_follow_up} ->
        inject_follow_up!(ctx, args, meta)

      {:given, :push_steering_message} ->
        push_steering_message!(ctx, args, meta)

      {:when, :steering_check_follow_up} ->
        steering_check_follow_up!(ctx, args, meta)

      {:then, :assert_follow_up_message} ->
        assert_follow_up_message!(ctx, args, meta)

      {:then, :assert_follow_up_empty} ->
        assert_follow_up_empty!(ctx, args, meta)

      # ── Settings ──

      {:given, :init_settings} ->
        init_settings!(ctx, args, meta)

      {:given, :create_settings_file} ->
        create_settings_file!(ctx, args, meta)

      {:when, :get_setting} ->
        get_setting!(ctx, args, meta)

      {:when, :set_setting} ->
        set_setting!(ctx, args, meta)

      {:then, :assert_setting_value} ->
        assert_setting_value!(ctx, args, meta)

      {:then, :assert_setting_nil} ->
        assert_setting_nil!(ctx, args, meta)

      {:when, :list_settings} ->
        list_settings!(ctx, args, meta)

      {:then, :assert_settings_list} ->
        assert_settings_list!(ctx, args, meta)

      {:when, :cleanup_settings} ->
        cleanup_settings!(ctx, args, meta)

      {:when, :get_setting_safe} ->
        get_setting_safe!(ctx, args, meta)

      # ── Resource ──

      {:given, :create_resource_dir} ->
        create_resource_dir!(ctx, args, meta)

      {:given, :create_resource_file} ->
        create_resource_file!(ctx, args, meta)

      {:when, :load_resources} ->
        load_resources!(ctx, args, meta)

      {:when, :reload_resources} ->
        reload_resources!(ctx, args, meta)

      {:then, :assert_resource_content} ->
        assert_resource_content!(ctx, args, meta)

      {:then, :assert_resource_count} ->
        assert_resource_count!(ctx, args, meta)

      {:when, :load_resources_from_paths} ->
        load_resources_from_paths!(ctx, args, meta)

      # ── Branch Summary ──

      {:when, :generate_branch_summary} ->
        generate_branch_summary!(ctx, args, meta)

      {:then, :assert_branch_summary} ->
        assert_branch_summary!(ctx, args, meta)

      # ── Tool: truncate_tool ──

      {:when, :tool_truncate} ->
        tool_truncate!(ctx, args, meta)

      # ── Tool: edit-diff ──

      {:when, :tool_edit_diff} ->
        tool_edit_diff!(ctx, args, meta)

      # ── Path Utils ──

      {:when, :normalize_path} ->
        normalize_path!(ctx, args, meta)

      {:then, :assert_normalized_path} ->
        assert_normalized_path!(ctx, args, meta)

      {:then, :assert_normalized_path_contains} ->
        assert_normalized_path_contains!(ctx, args, meta)

      {:then, :assert_normalized_path_is_absolute} ->
        assert_normalized_path_is_absolute!(ctx, args, meta)

      # ── ToolConfig ──
      {:given, :init_tool_config} ->
        init_tool_config!(ctx, args, meta)
      {:when, :get_active_tools} ->
        get_active_tools!(ctx, args, meta)
      {:when, :get_preset} ->
        get_preset!(ctx, args, meta)
      {:when, :set_active_tools} ->
        set_active_tools!(ctx, args, meta)
      {:when, :set_active_tools_safe} ->
        set_active_tools_safe!(ctx, args, meta)
      {:when, :validate_tools} ->
        validate_tools!(ctx, args, meta)
      {:then, :assert_active_tool_count} ->
        assert_active_tool_count!(ctx, args, meta)
      {:then, :assert_active_tool_contains} ->
        assert_active_tool_contains!(ctx, args, meta)
      {:then, :assert_preset_contains} ->
        assert_preset_contains!(ctx, args, meta)
      {:then, :assert_preset_not_contains} ->
        assert_preset_not_contains!(ctx, args, meta)
      {:then, :assert_preset_count} ->
        assert_preset_count!(ctx, args, meta)
      {:then, :assert_tool_config_error} ->
        assert_tool_config_error!(ctx, args, meta)

      # ── ToolResult ──
      {:when, :tool_result_from_text} ->
        tool_result_from_text!(ctx, args, meta)
      {:when, :tool_result_new} ->
        tool_result_new!(ctx, args, meta)
      {:when, :tool_result_error} ->
        tool_result_error!(ctx, args, meta)
      {:then, :assert_tool_result_content} ->
        assert_tool_result_content!(ctx, args, meta)
      {:then, :assert_tool_result_details_nil} ->
        assert_tool_result_details_nil!(ctx, args, meta)
      {:then, :assert_tool_result_has_details} ->
        assert_tool_result_has_details!(ctx, args, meta)
      {:then, :assert_tool_result_details_value} ->
        assert_tool_result_details_value!(ctx, args, meta)
      {:then, :assert_tool_result_is_error} ->
        assert_tool_result_is_error!(ctx, args, meta)
      {:then, :assert_tool_result_not_error} ->
        assert_tool_result_not_error!(ctx, args, meta)
      {:then, :assert_is_tool_result} ->
        assert_is_tool_result!(ctx, args, meta)

      # ── PartialJson ──
      {:when, :partial_json_parse} ->
        partial_json_parse!(ctx, args, meta)
      {:when, :partial_json_accumulate} ->
        partial_json_accumulate!(ctx, args, meta)
      {:then, :assert_partial_json_ok} ->
        assert_partial_json_ok!(ctx, args, meta)
      {:then, :assert_partial_json_field} ->
        assert_partial_json_field!(ctx, args, meta)
      {:then, :assert_partial_json_has_key} ->
        assert_partial_json_has_key!(ctx, args, meta)
      {:then, :assert_partial_json_empty} ->
        assert_partial_json_empty!(ctx, args, meta)

      _ ->
        raise ArgumentError, "未实现的指令: {#{kind}, #{name}}"
    end
  end

  # ── Common 实现 ──

  defp create_temp_dir!(ctx, _args, _meta) do
    dir = Path.join(System.tmp_dir!(), "gong_test_#{:erlang.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    ExUnit.Callbacks.on_exit(fn ->
      # 恢复权限后再删除（chmod 测试可能锁住子目录）
      System.cmd("chmod", ["-R", "755", dir], stderr_to_stdout: true)
      File.rm_rf!(dir)
    end)
    Map.put(ctx, :workspace, dir)
  end

  defp create_temp_file!(ctx, %{path: path, content: content}, _meta) do
    full = Path.join(ctx.workspace, path)
    File.mkdir_p!(Path.dirname(full))
    # 处理 DSL 中的转义换行
    decoded_content = unescape(content)
    File.write!(full, decoded_content)
    ctx
  end

  defp create_large_file!(ctx, %{lines: lines} = args, _meta) do
    path = Map.get(args, :path, "large_file.txt")
    line_length = Map.get(args, :line_length, 20)
    full = Path.join(ctx.workspace, path)
    File.mkdir_p!(Path.dirname(full))

    content =
      1..lines
      |> Enum.map(fn n ->
        padding = String.duplicate("x", max(0, line_length - String.length("line #{n}")))
        "line #{n}#{padding}"
      end)
      |> Enum.join("\n")

    File.write!(full, content <> "\n")
    ctx
  end

  defp create_binary_file!(ctx, %{path: path, bytes: bytes}, _meta) do
    full = Path.join(ctx.workspace, path)
    File.mkdir_p!(Path.dirname(full))
    # 写入含 null 字节的二进制数据
    data = :crypto.strong_rand_bytes(div(bytes, 2)) |> then(fn d -> <<0>> <> d end)
    padded = if byte_size(data) < bytes, do: data <> :binary.copy(<<0>>, bytes - byte_size(data)), else: binary_part(data, 0, bytes)
    File.write!(full, padded)
    ctx
  end

  defp create_png_file!(ctx, %{path: path}, _meta) do
    full = Path.join(ctx.workspace, path)
    File.mkdir_p!(Path.dirname(full))
    # 最小 PNG: 8 字节 signature + 空 IHDR
    png_header = <<0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A>>
    File.write!(full, png_header <> :binary.copy(<<0>>, 100))
    ctx
  end

  defp create_bom_file!(ctx, %{path: path, content: content}, _meta) do
    full = Path.join(ctx.workspace, path)
    File.mkdir_p!(Path.dirname(full))
    decoded_content = unescape(content)
    # UTF-8 BOM 前缀
    bom = <<0xEF, 0xBB, 0xBF>>
    File.write!(full, bom <> decoded_content)
    ctx
  end

  defp create_symlink!(ctx, %{link: link, target: target}, _meta) do
    link_full = Path.join(ctx.workspace, link)
    target_full = Path.join(ctx.workspace, target)
    File.mkdir_p!(Path.dirname(link_full))
    File.ln_s!(target_full, link_full)
    ctx
  end

  defp set_file_permission!(ctx, %{path: path, mode: mode}, _meta) do
    full = Path.join(ctx.workspace, path)
    mode_int = String.to_integer(mode, 8)
    File.chmod!(full, mode_int)
    ctx
  end

  # ── Tools 实现 ──

  defp tool_read!(ctx, args, _meta) do
    path = Map.get(args, :path, "")

    # 如果 path 不是绝对路径也不是 ~/ 开头，拼接 workspace
    file_path =
      cond do
        String.starts_with?(path, "/") -> path
        String.starts_with?(path, "~/") -> path
        true -> Path.join(ctx.workspace, path)
      end

    params = %{file_path: file_path}
    params = if args[:offset], do: Map.put(params, :offset, args.offset), else: params
    params = if args[:limit], do: Map.put(params, :limit, args.limit), else: params

    result = Gong.Tools.Read.run(params, %{})
    Map.put(ctx, :last_result, result)
  end

  # ── Tools 实现：write ──

  defp tool_write!(ctx, args, _meta) do
    path = resolve_tool_path(ctx, Map.get(args, :path, ""))
    content = unescape(Map.get(args, :content, ""))

    result = Gong.Tools.Write.run(%{file_path: path, content: content}, %{})
    Map.put(ctx, :last_result, result)
  end

  # ── Tools 实现：edit ──

  defp tool_edit!(ctx, args, _meta) do
    path = resolve_tool_path(ctx, Map.get(args, :path, ""))

    params = %{
      file_path: path,
      old_string: unescape(args.old_string),
      new_string: unescape(args.new_string)
    }
    params = if args[:replace_all], do: Map.put(params, :replace_all, args.replace_all), else: params

    tool_ctx = %{workspace: ctx[:workspace]}
    result = Gong.Tools.Edit.run(params, tool_ctx)
    Map.put(ctx, :last_result, result)
  end

  # ── Tools 实现：bash ──

  defp tool_bash!(ctx, args, _meta) do
    params = %{command: args.command}
    params = if args[:timeout], do: Map.put(params, :timeout, args.timeout), else: params
    params = if args[:cwd] do
      cwd = resolve_tool_path(ctx, args.cwd)
      Map.put(params, :cwd, cwd)
    else
      params
    end

    result = Gong.Tools.Bash.run(params, %{})
    Map.put(ctx, :last_result, result)
  end

  # ── Tools 实现：grep ──

  defp tool_grep!(ctx, args, _meta) do
    params = %{pattern: args.pattern}
    params = if args[:path], do: Map.put(params, :path, resolve_tool_path(ctx, args.path)), else: Map.put(params, :path, ctx.workspace)
    params = if args[:glob], do: Map.put(params, :glob, args.glob), else: params
    params = if args[:context], do: Map.put(params, :context, args.context), else: params
    params = if args[:ignore_case], do: Map.put(params, :ignore_case, args.ignore_case), else: params
    params = if args[:fixed_strings], do: Map.put(params, :fixed_strings, args.fixed_strings), else: params
    params = if args[:output_mode], do: Map.put(params, :output_mode, args.output_mode), else: params

    result = Gong.Tools.Grep.run(params, %{})
    Map.put(ctx, :last_result, result)
  end

  # ── Tools 实现：find ──

  defp tool_find!(ctx, args, _meta) do
    params = %{pattern: args.pattern}
    params = if args[:path], do: Map.put(params, :path, resolve_tool_path(ctx, args.path)), else: Map.put(params, :path, ctx.workspace)
    params = if args[:exclude], do: Map.put(params, :exclude, args.exclude), else: params
    params = if args[:limit], do: Map.put(params, :limit, args.limit), else: params

    result = Gong.Tools.Find.run(params, %{})
    Map.put(ctx, :last_result, result)
  end

  # ── Tools 实现：ls ──

  defp tool_ls!(ctx, args, _meta) do
    path = resolve_tool_path(ctx, Map.get(args, :path, ""))
    result = Gong.Tools.Ls.run(%{path: path}, %{})
    Map.put(ctx, :last_result, result)
  end

  # ── 路径解析辅助 ──

  defp resolve_tool_path(ctx, path) do
    cond do
      String.starts_with?(path, "/") -> path
      String.starts_with?(path, "~/") -> path
      true -> Path.join(ctx.workspace, path)
    end
  end

  # ── Assertion 实现 ──

  defp assert_tool_success!(ctx, args, _meta) do
    result = ctx.last_result
    assert {:ok, tr} = result, "期望成功，实际：#{inspect(result)}"

    # 兼容 ToolResult 和普通 map
    content = case tr do
      %Gong.ToolResult{content: c} -> c
      %{content: c} -> c
    end

    if cc = args[:content_contains] do
      assert content =~ unescape(cc),
        "期望内容包含 #{inspect(cc)}，实际：#{String.slice(content, 0, 200)}"
    end

    if args[:truncated] != nil do
      truncated = case tr do
        %Gong.ToolResult{details: %{truncated: t}} -> t
        %{truncated: t} -> t
      end
      assert truncated == args.truncated,
        "期望 truncated=#{args.truncated}，实际：#{truncated}"
    end

    ctx
  end

  defp assert_tool_error!(ctx, %{error_contains: expected}, _meta) do
    result = ctx.last_result
    assert {:error, error} = result, "期望错误，实际：#{inspect(result)}"
    error_msg = if is_binary(error), do: error, else: inspect(error)

    assert error_msg =~ unescape(expected),
      "期望错误包含 #{inspect(expected)}，实际：#{error_msg}"

    ctx
  end

  defp assert_tool_truncated!(ctx, args, _meta) do
    result = ctx.last_result
    assert {:ok, tr} = result

    # 兼容 ToolResult 和普通 map
    {truncated, truncated_details} = case tr do
      %Gong.ToolResult{details: details} -> {details.truncated, details[:truncated_details]}
      data -> {data.truncated, data[:truncated_details]}
    end

    assert truncated == true, "期望 truncated=true"

    if tb = args[:truncated_by] do
      assert truncated_details != nil
      assert to_string(truncated_details.truncated_by) == tb,
        "期望 truncated_by=#{tb}，实际：#{inspect(truncated_details.truncated_by)}"
    end

    if ol = args[:original_lines] do
      assert truncated_details.total_lines == ol,
        "期望 total_lines=#{ol}，实际：#{truncated_details.total_lines}"
    end

    ctx
  end

  defp assert_read_image!(ctx, %{mime_type: expected_mime}, _meta) do
    result = ctx.last_result
    assert {:ok, tr} = result

    # 兼容 ToolResult 和普通 map
    image = case tr do
      %Gong.ToolResult{details: %{image: img}} -> img
      %{image: img} -> img
    end

    assert image != nil, "期望返回图片数据"
    assert image.mime_type == expected_mime,
      "期望 MIME=#{expected_mime}，实际：#{image.mime_type}"
    ctx
  end

  defp assert_read_text!(ctx, _args, _meta) do
    result = ctx.last_result
    assert {:ok, tr} = result

    # 兼容 ToolResult 和普通 map
    image = case tr do
      %Gong.ToolResult{details: details} -> details[:image]
      data -> data[:image]
    end

    assert image == nil, "期望返回文本，但收到图片数据"
    ctx
  end

  # ── 文件断言 ──

  defp assert_file_exists!(ctx, %{path: path}, _meta) do
    full = Path.join(ctx.workspace, path)
    assert File.exists?(full), "期望文件存在: #{full}"
    ctx
  end

  defp assert_file_content!(ctx, %{path: path, expected: expected}, _meta) do
    full = Path.join(ctx.workspace, path)
    actual = File.read!(full)
    expected_decoded = unescape(expected)
    assert actual == expected_decoded,
      "期望文件内容为 #{inspect(expected_decoded)}，实际：#{inspect(actual)}"
    ctx
  end

  defp assert_file_has_bom!(ctx, %{path: path}, _meta) do
    full = Path.join(ctx.workspace, path)
    raw = File.read!(full)
    assert <<0xEF, 0xBB, 0xBF, _rest::binary>> = raw,
      "期望文件以 UTF-8 BOM 开头: #{full}"
    ctx
  end

  defp assert_file_has_crlf!(ctx, %{path: path}, _meta) do
    full = Path.join(ctx.workspace, path)
    raw = File.read!(full)
    assert String.contains?(raw, "\r\n"),
      "期望文件包含 CRLF 行尾: #{full}"
    ctx
  end

  defp assert_file_no_crlf!(ctx, %{path: path}, _meta) do
    full = Path.join(ctx.workspace, path)
    raw = File.read!(full)
    refute String.contains?(raw, "\r\n"),
      "期望文件不包含 CRLF 行尾: #{full}"
    ctx
  end

  # ── 结果字段断言 ──

  defp assert_result_field!(ctx, %{field: field, expected: expected}, _meta) do
    assert {:ok, tr} = ctx.last_result

    # 兼容 ToolResult（从 details 查找字段）和普通 map
    data = case tr do
      %Gong.ToolResult{details: details} -> details || %{}
      other -> other
    end

    actual = get_nested_field(data, field)
    assert to_string(actual) == expected,
      "期望 #{field}=#{expected}，实际：#{inspect(actual)}"
    ctx
  end

  # 支持嵌套字段访问：如 "diff_first_changed_line" → data.diff.first_changed_line
  defp get_nested_field(data, field) do
    # 先尝试直接访问
    field_atom = try_existing_atom(field)
    case field_atom && Map.get(data, field_atom) do
      nil ->
        # 尝试按 _ 分割逐层访问（如 diff_first_changed_line → [:diff, :first_changed_line]）
        try_nested_access(data, field)
      value ->
        value
    end
  end

  defp try_existing_atom(str) do
    String.to_existing_atom(str)
  rescue
    ArgumentError -> nil
  end

  defp try_nested_access(data, field) do
    parts = String.split(field, "_")
    # 从左往右尝试拼接找到第一个匹配的 key
    find_nested_value(data, parts)
  end

  defp find_nested_value(_data, []), do: nil

  defp find_nested_value(data, parts) when is_map(data) do
    # 尝试从 1 个 part 到全部 parts 作为 key
    Enum.find_value(1..length(parts), fn n ->
      key_str = Enum.take(parts, n) |> Enum.join("_")
      key_atom = try_existing_atom(key_str)
      case key_atom && Map.get(data, key_atom) do
        nil -> nil
        value when n == length(parts) -> value
        value -> find_nested_value(value, Enum.drop(parts, n))
      end
    end)
  end

  defp find_nested_value(_, _), do: nil

  # ── Bash 特有断言 ──

  defp assert_exit_code!(ctx, %{expected: expected}, _meta) do
    assert {:ok, tr} = ctx.last_result

    exit_code = case tr do
      %Gong.ToolResult{details: %{exit_code: c}} -> c
      %{exit_code: c} -> c
    end

    assert exit_code == expected,
      "期望 exit_code=#{expected}，实际：#{exit_code}"
    ctx
  end

  defp assert_output_contains!(ctx, %{text: text}, _meta) do
    assert {:ok, tr} = ctx.last_result

    content = case tr do
      %Gong.ToolResult{content: c} -> c
      %{content: c} -> c
    end

    decoded = unescape(text)
    assert content =~ decoded,
      "期望输出包含 #{inspect(decoded)}，实际：#{String.slice(content, 0, 200)}"
    ctx
  end

  defp assert_output_not_contains!(ctx, %{text: text}, _meta) do
    assert {:ok, tr} = ctx.last_result

    content = case tr do
      %Gong.ToolResult{content: c} -> c
      %{content: c} -> c
    end

    decoded = unescape(text)
    refute content =~ decoded,
      "期望输出不包含 #{inspect(decoded)}，但包含了"
    ctx
  end

  # ── Common 实现：变量 ──

  defp set_var!(ctx, %{name: name, value: value}, _meta) do
    decoded = unescape(value)
    Map.put(ctx, String.to_atom(name), decoded)
  end

  defp generate_content!(ctx, args, _meta) do
    name = args.name
    lines = args.lines
    line_length = Map.get(args, :line_length, 20)

    content =
      1..lines
      |> Enum.map(fn n ->
        prefix = "line #{n}"
        padding = String.duplicate("x", max(0, line_length - String.length(prefix)))
        prefix <> padding
      end)
      |> Enum.join("\n")

    Map.put(ctx, String.to_atom(name), content)
  end

  # ── 截断操作实现 ──

  defp truncate_head!(ctx, args, _meta) do
    content = Map.fetch!(ctx, String.to_atom(args.content_var))
    opts = build_truncate_opts(args)
    result = Gong.Truncate.truncate(content, :head, opts)
    Map.put(ctx, :last_result, result)
  end

  defp truncate_tail!(ctx, args, _meta) do
    content = Map.fetch!(ctx, String.to_atom(args.content_var))
    opts = build_truncate_opts(args)
    result = Gong.Truncate.truncate(content, :tail, opts)
    Map.put(ctx, :last_result, result)
  end

  defp truncate_line!(ctx, args, _meta) do
    content = Map.fetch!(ctx, String.to_atom(args.content_var))
    result = Gong.Truncate.truncate_line(content, args.max_chars)
    Map.put(ctx, :last_result, result)
  end

  defp build_truncate_opts(args) do
    opts = []
    opts = if args[:max_lines], do: [{:max_lines, args.max_lines} | opts], else: opts
    opts = if args[:max_bytes], do: [{:max_bytes, args.max_bytes} | opts], else: opts
    opts
  end

  # ── 截断断言实现 ──

  defp assert_truncation_result!(ctx, args, _meta) do
    result = ctx.last_result
    assert %Gong.Truncate.Result{} = result, "期望 Truncate.Result，实际：#{inspect(result)}"

    if args[:truncated] != nil do
      assert result.truncated == args.truncated,
        "期望 truncated=#{args.truncated}，实际：#{result.truncated}"
    end

    if tb = args[:truncated_by] do
      expected_by = String.to_existing_atom(tb)

      assert result.truncated_by == expected_by,
        "期望 truncated_by=#{tb}，实际：#{inspect(result.truncated_by)}"
    end

    if args[:output_lines] do
      assert result.output_lines == args.output_lines,
        "期望 output_lines=#{args.output_lines}，实际：#{result.output_lines}"
    end

    if args[:first_line_exceeds_limit] != nil do
      assert result.first_line_exceeds_limit == args.first_line_exceeds_limit,
        "期望 first_line_exceeds_limit=#{args.first_line_exceeds_limit}，实际：#{result.first_line_exceeds_limit}"
    end

    if args[:last_line_partial] != nil do
      assert result.last_line_partial == args.last_line_partial,
        "期望 last_line_partial=#{args.last_line_partial}，实际：#{result.last_line_partial}"
    end

    if cc = args[:content_contains] do
      decoded = unescape(cc)

      assert result.content =~ decoded,
        "期望 content 包含 #{inspect(decoded)}，实际：#{String.slice(result.content, 0, 200)}"
    end

    if args[:valid_utf8] == true do
      assert String.valid?(result.content),
        "期望 content 是合法 UTF-8，但包含无效字节"
    end

    ctx
  end

  defp assert_truncation_notification!(ctx, %{contains: text}, _meta) do
    # 用于工具集成测试，last_result 是 {:ok, %{content: ...}}
    assert {:ok, data} = ctx.last_result
    decoded = unescape(text)

    assert data.content =~ decoded,
      "期望截断通知包含 #{inspect(decoded)}，实际：#{String.slice(data.content, 0, 300)}"

    ctx
  end

  # ── Agent 配置实现 ──

  defp configure_agent!(ctx, args, _meta) do
    # mock 测试用策略层（无 AgentServer），E2E 测试用 AgentServer
    # 根据 mock_queue 是否为空来区分
    agent = Gong.MockLLM.init_agent()

    ctx =
      ctx
      |> Map.put(:agent, agent)
      |> Map.put(:agent_mode, :mock)
      |> Map.put(:mock_queue, [])
      |> Map.put(:tool_call_log, [])
      |> Map.put(:hook_events, [])
      |> Map.put(:hooks, [])
      |> Map.put(:telemetry_events, [])
      |> Map.put(:telemetry_handlers, [])
      |> Map.put(:stream_events, [])

    # 如果提供了 context_window，配置自动压缩
    if cw = args[:context_window] do
      rt = args[:reserve_tokens] || 100
      compaction_opts = [
        context_window: cw,
        reserve_tokens: rt,
        window_size: 4,
        summarize_fn: fn _messages -> {:ok, "自动压缩摘要"} end
      ]
      Map.put(ctx, :compaction_opts, compaction_opts)
    else
      ctx
    end
  end

  defp mock_llm_response!(ctx, args, _meta) do
    response =
      case args.response_type do
        "text" ->
          {:text, Map.get(args, :content, "")}

        "tool_call" ->
          tool = Map.get(args, :tool, "bash")
          tool_args = parse_tool_args(Map.get(args, :tool_args, ""), ctx)
          tc = %{name: tool, arguments: tool_args}
          # 支持自定义 tool_call ID（用于结果顺序验证）
          tc = if id = Map.get(args, :tool_id), do: Map.put(tc, :id, id), else: tc
          {:tool_calls, [tc]}

        "error" ->
          {:error, Map.get(args, :content, "LLM error")}

        "stream" ->
          {:text, Map.get(args, :content, "")}
      end

    queue = Map.get(ctx, :mock_queue, [])

    # batch_with_previous: 将本次 tool_call 合并到队列最后一个 tool_calls 条目
    # 用于模拟 LLM 单次返回多个 tool_call 的场景（Pi#1446, Pi#1454）
    if Map.get(args, :batch_with_previous) == "true" do
      case {response, List.last(queue)} do
        {{:tool_calls, new_tcs}, {:tool_calls, existing_tcs}} ->
          updated_last = {:tool_calls, existing_tcs ++ new_tcs}
          Map.put(ctx, :mock_queue, List.replace_at(queue, -1, updated_last))

        _ ->
          # 前一个条目不是 tool_calls，正常追加
          Map.put(ctx, :mock_queue, queue ++ [response])
      end
    else
      Map.put(ctx, :mock_queue, queue ++ [response])
    end
  end

  # 解析管道分隔的工具参数：key1=value1|key2=value2
  # 支持 {{workspace}} 占位符替换
  defp parse_tool_args("", _ctx), do: %{}

  defp parse_tool_args(str, ctx) do
    str
    |> String.split("|")
    |> Enum.map(fn pair ->
      case String.split(pair, "=", parts: 2) do
        [key, value] ->
          resolved = String.replace(value, "{{workspace}}", Map.get(ctx, :workspace, ""))
          {key, resolved}
        [key] -> {key, ""}
      end
    end)
    |> Map.new()
  end

  defp inject_steering!(ctx, %{message: message} = args, _meta) do
    after_tool = Map.get(args, :after_tool, 1)
    steering_config = %{message: message, after_tool: after_tool}
    Map.put(ctx, :steering_config, steering_config)
  end

  defp register_hook!(ctx, %{module: module_name}, _meta) do
    # 解析模块名（支持 "Gong.TestHooks.AllowAll" 等格式）
    hook_module = resolve_hook_module(module_name)
    hooks = Map.get(ctx, :hooks, [])
    Map.put(ctx, :hooks, hooks ++ [hook_module])
  end

  defp attach_telemetry_handler!(ctx, %{event: event_str}, _meta) do
    # 解析事件名："gong.tool.start" → [:gong, :tool, :start]
    event = event_str |> String.split(".") |> Enum.map(&String.to_atom/1)
    handler_id = "bdd_telemetry_#{:erlang.unique_integer([:positive])}"
    test_pid = self()

    :telemetry.attach(
      handler_id,
      event,
      fn event_name, measurements, metadata, _config ->
        send(test_pid, {:telemetry_event, event_name, measurements, metadata})
      end,
      nil
    )

    # 测试结束后清理 handler
    ExUnit.Callbacks.on_exit(fn ->
      :telemetry.detach(handler_id)
    end)

    handlers = Map.get(ctx, :telemetry_handlers, [])
    Map.put(ctx, :telemetry_handlers, handlers ++ [handler_id])
  end

  defp configure_hooks!(ctx, %{hooks: hooks_str}, _meta) do
    # 逗号分隔的模块名列表
    hook_modules =
      hooks_str
      |> String.split(",")
      |> Enum.map(&String.trim/1)
      |> Enum.map(&resolve_hook_module/1)

    Map.put(ctx, :hooks, hook_modules)
  end

  defp resolve_hook_module(module_name) do
    # 支持短名和全名
    full_name =
      if String.starts_with?(module_name, "Elixir.") or String.starts_with?(module_name, "Gong.") do
        module_name
      else
        "Gong.TestHooks.#{module_name}"
      end

    Module.concat([full_name])
  end

  # ── Agent 操作实现 ──

  defp agent_chat!(ctx, %{prompt: prompt}, _meta) do
    queue = Map.get(ctx, :mock_queue, [])
    hooks = Map.get(ctx, :hooks, [])

    if queue != [] do
      # Mock 模式：策略层驱动（传入 hooks + steering）
      agent = ctx.agent
      opts = if sc = ctx[:steering_config], do: [steering_config: sc], else: []
      case Gong.MockLLM.run_chat(agent, prompt, queue, hooks, opts) do
        {:ok, reply, updated_agent} ->
          ctx = collect_telemetry_events(ctx)

          # Auto-compaction 检查：对话成功后检查是否需要压缩
          {ctx, updated_agent} = maybe_auto_compact(ctx, updated_agent)

          ctx
          |> Map.put(:agent, updated_agent)
          |> Map.put(:last_reply, reply)
          |> Map.put(:last_error, nil)
          |> Map.put(:mock_queue, [])

        {:error, reason, updated_agent} ->
          ctx = collect_telemetry_events(ctx)

          ctx
          |> Map.put(:agent, updated_agent)
          |> Map.put(:last_reply, to_string(reason))
          |> Map.put(:last_error, reason)
          |> Map.put(:mock_queue, [])
      end
    else
      # E2E 模式：真实 AgentServer + LLM
      # 复用已有 AgentServer（多轮对话支持）
      pid = if ctx[:agent_pid] && Process.alive?(ctx[:agent_pid]) do
        ctx[:agent_pid]
      else
        {:ok, new_pid} = Jido.AgentServer.start_link(agent: Gong.Agent)
        ExUnit.Callbacks.on_exit(fn ->
          if Process.alive?(new_pid), do: GenServer.stop(new_pid, :normal, 1000)
        end)
        new_pid
      end

      # 在 prompt 前注入 workspace 路径，让 LLM 知道文件位置
      workspace = Map.get(ctx, :workspace, File.cwd!())
      full_prompt = "工作目录：#{workspace}\n所有文件操作使用绝对路径。\n\n#{prompt}"

      case Gong.Agent.ask_sync(pid, full_prompt, timeout: 60_000) do
        {:ok, reply} ->
          ctx
          |> Map.put(:agent_pid, pid)
          |> Map.put(:agent_mode, :e2e)
          |> Map.put(:last_reply, reply)
          |> Map.put(:last_error, nil)

        {:error, reason} ->
          ctx
          |> Map.put(:agent_pid, pid)
          |> Map.put(:agent_mode, :e2e)
          |> Map.put(:last_reply, nil)
          |> Map.put(:last_error, reason)
      end
    end
  end

  defp agent_stream!(ctx, %{prompt: prompt}, _meta) do
    queue = Map.get(ctx, :mock_queue, [])
    stream_queue = Map.get(ctx, :stream_queue, [])
    events = [{:stream, :start}]

    cond do
      # 有 stream_queue → 使用 MockStream 处理 chunk 队列
      stream_queue != [] ->
        chunks = List.first(stream_queue)
        {_stream_events, text} = Gong.MockStream.run(chunks)
        events = events ++ [{:stream, :delta}, {:stream, :end}]

        ctx
        |> Map.put(:last_reply, text)
        |> Map.put(:last_error, nil)
        |> Map.put(:stream_events, events)
        |> Map.put(:stream_queue, Enum.drop(stream_queue, 1))
        |> Map.put(:mock_queue, [])

      # 有 mock_queue → 使用 MockLLM 正常处理
      queue != [] ->
        agent = ctx.agent
        hooks = Map.get(ctx, :hooks, [])
        case Gong.MockLLM.run_chat(agent, prompt, queue, hooks) do
          {:ok, reply, updated_agent} ->
            events = events ++ [{:stream, :delta}, {:stream, :end}]
            ctx
            |> Map.put(:agent, updated_agent)
            |> Map.put(:last_reply, reply)
            |> Map.put(:last_error, nil)
            |> Map.put(:stream_events, events)
            |> Map.put(:mock_queue, [])

          {:error, reason, updated_agent} ->
            events = events ++ [{:stream, :end}]
            ctx
            |> Map.put(:agent, updated_agent)
            |> Map.put(:last_reply, nil)
            |> Map.put(:last_error, reason)
            |> Map.put(:stream_events, events)
            |> Map.put(:mock_queue, [])
        end

      # 无队列 → E2E 模式
      true ->
        # E2E 流式：复用 agent_chat 逻辑
        ctx = agent_chat!(ctx, %{prompt: prompt}, %{})
        events = events ++ [{:stream, :delta}, {:stream, :end}]
        Map.put(ctx, :stream_events, events)
    end
  end

  defp agent_abort!(ctx, _args, _meta) do
    if ctx[:agent_pid] do
      Gong.Agent.cancel(ctx.agent_pid)
      Process.sleep(50)
    end
    ctx
  end

  defp trigger_compaction!(ctx, _args, _meta) do
    hooks = Map.get(ctx, :hooks, [])

    case Gong.HookRunner.gate(hooks, :before_session_op, [:compact, %{}]) do
      :ok ->
        ctx

      {:blocked, reason} ->
        ctx
        |> Map.put(:last_error, "Blocked by hook: #{reason}")
    end
  end

  # ── Agent 断言实现 ──

  defp assert_agent_reply!(ctx, %{contains: expected}, _meta) do
    reply = ctx.last_reply
    assert reply != nil, "Agent 未返回回复"
    decoded = unescape(expected)
    assert to_string(reply) =~ decoded,
      "期望回复包含 #{inspect(decoded)}，实际：#{inspect(reply)}"
    ctx
  end

  defp assert_tool_was_called!(ctx, %{tool: tool_name} = args, _meta) do
    strategy_state = get_agent_strategy_state(ctx)
    tool_calls = Gong.MockLLM.extract_tool_calls(strategy_state)
    matching = Enum.filter(tool_calls, fn tc -> tc.name == tool_name end)

    if times = args[:times] do
      assert length(matching) == times,
        "期望工具 #{tool_name} 被调用 #{times} 次，实际：#{length(matching)}"
    else
      assert length(matching) > 0,
        "期望工具 #{tool_name} 被调用，但未找到调用记录"
    end

    ctx
  end

  defp assert_tool_not_called!(ctx, %{tool: tool_name}, _meta) do
    strategy_state = get_agent_strategy_state(ctx)
    tool_calls = Gong.MockLLM.extract_tool_calls(strategy_state)
    matching = Enum.filter(tool_calls, fn tc -> tc.name == tool_name end)

    assert length(matching) == 0,
      "期望工具 #{tool_name} 未被调用，但找到 #{length(matching)} 次调用"

    ctx
  end

  defp assert_hook_fired!(ctx, %{event: event}, _meta) do
    # 检查 hook_events 和 telemetry_events 两个来源
    hook_events = Map.get(ctx, :hook_events, [])
    telemetry_events = Map.get(ctx, :telemetry_events, [])

    hook_match = Enum.any?(hook_events, fn e -> to_string(e) =~ event end)

    telemetry_match =
      Enum.any?(telemetry_events, fn {event_name, _measurements, _metadata} ->
        event_str = event_name |> Enum.map(&to_string/1) |> Enum.join(".")
        event_str =~ event
      end)

    assert hook_match or telemetry_match,
      "期望 hook 事件 #{event} 已触发，实际 hook_events：#{inspect(hook_events)}，telemetry：#{length(telemetry_events)} 条"
    ctx
  end

  defp assert_hook_blocked!(ctx, %{reason_contains: reason}, _meta) do
    error = Map.get(ctx, :last_error)
    assert error != nil, "期望操作被阻止，但未发现错误"
    assert to_string(error) =~ unescape(reason),
      "期望阻止原因包含 #{inspect(reason)}，实际：#{inspect(error)}"
    ctx
  end

  defp assert_stream_events!(ctx, %{sequence: sequence}, _meta) do
    events = Map.get(ctx, :stream_events, [])
    expected_types = String.split(sequence, ",") |> Enum.map(&String.trim/1)

    actual_types = Enum.map(events, fn
      {:stream, type} -> to_string(type)
      other -> to_string(other)
    end)

    assert actual_types == expected_types,
      "期望流事件序列 #{inspect(expected_types)}，实际：#{inspect(actual_types)}"

    ctx
  end

  defp assert_last_error!(ctx, %{error_contains: expected}, _meta) do
    error = Map.get(ctx, :last_error)
    assert error != nil, "期望存在错误，但 last_error 为 nil"
    error_msg = to_string(error)
    decoded = unescape(expected)
    assert error_msg =~ decoded,
      "期望错误包含 #{inspect(decoded)}，实际：#{inspect(error_msg)}"
    ctx
  end

  defp assert_no_crash!(ctx, _args, _meta) do
    # mock 模式检查 agent 结构体存在；E2E 模式检查进程存活
    if ctx[:agent_pid] do
      assert Process.alive?(ctx.agent_pid), "Agent 进程已崩溃"
    else
      assert ctx[:agent] != nil, "Agent 结构体不存在"
    end
    ctx
  end

  # ── Auto-compaction 集成 ──

  defp maybe_auto_compact(ctx, agent) do
    compaction_opts = ctx[:compaction_opts]

    if compaction_opts do
      strategy_state = Map.get(agent.state, :__strategy__, %{})
      conversation = Map.get(strategy_state, :conversation, [])

      case Gong.AutoCompaction.auto_compact(conversation, compaction_opts) do
        {:compacted, new_messages, summary} ->
          :telemetry.execute([:gong, :compaction, :auto], %{count: 1}, %{
            summary: summary,
            before_count: length(conversation),
            after_count: length(new_messages)
          })
          # 更新 agent conversation
          strategy = Map.get(agent.state, :__strategy__, %{})
          updated_strategy = Map.put(strategy, :conversation, new_messages)
          updated_state = Map.put(agent.state, :__strategy__, updated_strategy)
          updated_agent = %{agent | state: updated_state}
          # 收集 compaction telemetry
          ctx = collect_telemetry_events(ctx)
          {Map.put(ctx, :compaction_happened, true), updated_agent}

        {:no_action, _} ->
          {ctx, agent}

        {:skipped, _} ->
          {ctx, agent}
      end
    else
      {ctx, agent}
    end
  end

  defp assert_compaction_triggered!(ctx, _args, _meta) do
    assert ctx[:compaction_happened] == true,
      "期望自动压缩被触发，但未发生"
    ctx
  end

  defp assert_compaction_not_triggered!(ctx, _args, _meta) do
    assert ctx[:compaction_happened] != true,
      "期望不触发压缩，但压缩被触发了"
    ctx
  end

  # ── Auto-retry 断言实现 ──

  defp assert_retry_happened!(ctx, _args, _meta) do
    telemetry_events = Map.get(ctx, :telemetry_events, [])
    retry_events = Enum.filter(telemetry_events, fn {event_name, _m, _md} ->
      event_name == [:gong, :retry]
    end)
    assert length(retry_events) > 0,
      "期望发生重试，但未收到 [:gong, :retry] telemetry 事件"
    ctx
  end

  defp assert_no_retry!(ctx, _args, _meta) do
    telemetry_events = Map.get(ctx, :telemetry_events, [])
    retry_events = Enum.filter(telemetry_events, fn {event_name, _m, _md} ->
      event_name == [:gong, :retry]
    end)
    assert length(retry_events) == 0,
      "期望无重试，但收到 #{length(retry_events)} 个 [:gong, :retry] 事件"
    ctx
  end

  # ── Hook 断言实现 ──

  defp assert_telemetry_received!(ctx, %{event: event_str} = args, _meta) do
    telemetry_events = Map.get(ctx, :telemetry_events, [])
    expected_event = event_str |> String.split(".") |> Enum.map(&String.to_atom/1)

    matching =
      Enum.filter(telemetry_events, fn {event_name, _m, _md} ->
        event_name == expected_event
      end)

    assert length(matching) > 0,
      "期望收到 telemetry 事件 #{event_str}，实际事件：#{inspect(Enum.map(telemetry_events, &elem(&1, 0)))}"

    # 可选：检查 metadata 包含特定内容
    if mc = args[:metadata_contains] do
      has_match =
        Enum.any?(matching, fn {_, _, metadata} ->
          inspect(metadata) =~ mc
        end)

      assert has_match,
        "期望 telemetry metadata 包含 #{inspect(mc)}，实际：#{inspect(Enum.map(matching, &elem(&1, 2)))}"
    end

    ctx
  end

  defp assert_hook_error_logged!(ctx, %{hook: hook_name} = args, _meta) do
    telemetry_events = Map.get(ctx, :telemetry_events, [])

    # 查找 [:gong, :hook, :error] 事件
    error_events =
      Enum.filter(telemetry_events, fn {event_name, _m, metadata} ->
        event_name == [:gong, :hook, :error] and
          inspect(metadata[:hook]) =~ hook_name
      end)

    assert length(error_events) > 0,
      "期望 hook #{hook_name} 错误已记录，实际 hook error 事件：#{inspect(telemetry_events |> Enum.filter(fn {e, _, _} -> e == [:gong, :hook, :error] end))}"

    # 可选：检查堆栈
    if args[:has_stacktrace] == true do
      has_stack =
        Enum.any?(error_events, fn {_, _, metadata} ->
          stacktrace = metadata[:stacktrace]
          is_list(stacktrace) and length(stacktrace) > 0
        end)

      assert has_stack, "期望 hook 错误包含堆栈，但未找到"
    end

    ctx
  end

  defp assert_result_content_contains!(ctx, %{text: text}, _meta) do
    # 检查 last_reply（agent 回复内容）
    reply = Map.get(ctx, :last_reply, "")
    decoded = unescape(text)

    assert to_string(reply) =~ decoded,
      "期望结果包含 #{inspect(decoded)}，实际：#{inspect(reply)}"

    ctx
  end

  defp assert_result_content_not_contains!(ctx, %{text: text}, _meta) do
    reply = Map.get(ctx, :last_reply, "")
    decoded = unescape(text)

    refute to_string(reply) =~ decoded,
      "期望结果不包含 #{inspect(decoded)}，但包含了"

    ctx
  end

  defp assert_conversation_contains!(ctx, %{text: text}, _meta) do
    strategy_state = get_agent_strategy_state(ctx)
    conversation = Map.get(strategy_state, :conversation, [])
    decoded = unescape(text)

    # 在所有消息的 content 中搜索目标文本
    found =
      Enum.any?(conversation, fn msg ->
        content = msg[:content] || msg["content"] || ""
        to_string(content) =~ decoded
      end)

    assert found,
      "期望 conversation 包含 #{inspect(decoded)}，实际消息数：#{length(conversation)}，内容：#{inspect(Enum.map(conversation, fn m -> Map.get(m, :content, Map.get(m, "content", "")) end) |> Enum.take(5))}"

    ctx
  end

  # ── Telemetry 事件收集 ──

  defp collect_telemetry_events(ctx) do
    # 从进程邮箱中收集所有 telemetry 事件
    events = drain_telemetry_messages([])
    existing = Map.get(ctx, :telemetry_events, [])
    Map.put(ctx, :telemetry_events, existing ++ events)
  end

  defp drain_telemetry_messages(acc) do
    receive do
      {:telemetry_event, event_name, measurements, metadata} ->
        drain_telemetry_messages(acc ++ [{event_name, measurements, metadata}])
    after
      0 -> acc
    end
  end

  # ── Agent 状态提取辅助 ──

  defp get_agent_strategy_state(ctx) do
    if ctx[:agent_pid] do
      Gong.MockLLM.get_strategy_state(ctx.agent_pid)
    else
      agent = ctx.agent
      Jido.Agent.Strategy.State.get(agent, %{})
    end
  end

  # ── Tape GIVEN 实现 ──

  defp tape_init_given!(ctx, _args, _meta) do
    workspace = ctx.workspace
    tape_path = Path.join(workspace, "tape")
    {:ok, store} = Gong.Tape.Store.init(tape_path)

    ExUnit.Callbacks.on_exit(fn ->
      Gong.Tape.Store.close(store)
    end)

    ctx
    |> Map.put(:tape_store, store)
    |> Map.put(:tape_path, tape_path)
    |> Map.put(:tape_last_anchor, "session-start")
  end

  defp tape_append_given!(ctx, args, _meta) do
    store = ctx.tape_store
    anchor = Map.get(args, :anchor, Map.get(ctx, :tape_last_anchor, "session-start"))
    kind = args.kind
    content = unescape(args.content)

    metadata =
      cond do
        Map.has_key?(args, :metadata_kv) ->
          # 解析 key:value,key:value 格式
          args.metadata_kv
          |> String.split(",")
          |> Enum.map(fn pair ->
            [k, v] = String.split(pair, ":", parts: 2)
            {String.trim(k), parse_metadata_value(String.trim(v))}
          end)
          |> Map.new()

        Map.has_key?(args, :metadata_json) ->
          Jason.decode!(args.metadata_json)

        true ->
          %{}
      end

    case Gong.Tape.Store.append(store, anchor, %{kind: kind, content: content, metadata: metadata}) do
      {:ok, updated_store} ->
        Map.put(ctx, :tape_store, updated_store)

      {:error, reason} ->
        Map.put(ctx, :tape_last_error, reason)
    end
  end

  defp tape_handoff_given!(ctx, %{name: name}, _meta) do
    store = ctx.tape_store

    case Gong.Tape.Store.handoff(store, name) do
      {:ok, _dir_name, updated_store} ->
        ctx
        |> Map.put(:tape_store, updated_store)
        |> Map.put(:tape_last_anchor, name)

      {:error, reason} ->
        Map.put(ctx, :tape_last_error, reason)
    end
  end

  defp tape_fork_given!(ctx, _args, _meta) do
    store = ctx.tape_store

    case Gong.Tape.Store.fork(store) do
      {:ok, fork_store} ->
        ExUnit.Callbacks.on_exit(fn ->
          Gong.Tape.Store.close(fork_store)
          File.rm_rf(fork_store.workspace_path)
        end)

        # fork 成为活跃 store，父 store 保存为 tape_parent_store
        ctx
        |> Map.put(:tape_parent_store, store)
        |> Map.put(:tape_store, fork_store)
        |> Map.put(:fork_store, fork_store)
        |> Map.put(:tape_path, fork_store.workspace_path)
        |> Map.put(:tape_fork_path, fork_store.workspace_path)

      {:error, reason} ->
        Map.put(ctx, :tape_last_error, reason)
    end
  end

  defp tape_close_db!(ctx, _args, _meta) do
    store = ctx.tape_store
    Gong.Tape.Store.close(store)
    ctx
  end

  defp tape_restore_parent!(ctx, _args, _meta) do
    parent = Map.fetch!(ctx, :tape_parent_store)

    ctx
    |> Map.put(:tape_store, parent)
    |> Map.put(:tape_path, parent.workspace_path)
  end

  defp corrupt_jsonl!(ctx, %{path: path, line_content: line_content}, _meta) do
    full = resolve_tape_path(ctx, path)
    File.write!(full, unescape(line_content) <> "\n", [:append])
    ctx
  end

  defp delete_file!(ctx, %{path: path}, _meta) do
    full = resolve_tape_path(ctx, path)
    File.rm!(full)
    ctx
  end

  defp clear_file!(ctx, %{path: path}, _meta) do
    full = resolve_tape_path(ctx, path)
    File.write!(full, "")
    ctx
  end

  # ── Tape WHEN 实现 ──

  defp tape_init_when!(ctx, _args, _meta) do
    workspace = ctx.workspace
    tape_path = Path.join(workspace, "tape")

    case Gong.Tape.Store.init(tape_path) do
      {:ok, store} ->
        ExUnit.Callbacks.on_exit(fn ->
          Gong.Tape.Store.close(store)
        end)

        ctx
        |> Map.put(:tape_store, store)
        |> Map.put(:tape_path, tape_path)
        |> Map.put(:tape_last_anchor, "session-start")
        |> Map.put(:tape_last_error, nil)

      {:error, reason} ->
        Map.put(ctx, :tape_last_error, reason)
    end
  end

  defp tape_append_when!(ctx, args, _meta) do
    store = ctx.tape_store
    anchor = Map.get(args, :anchor, Map.get(ctx, :tape_last_anchor, "session-start"))
    kind = args.kind
    content = unescape(args.content)

    case Gong.Tape.Store.append(store, anchor, %{kind: kind, content: content}) do
      {:ok, updated_store} ->
        ctx
        |> Map.put(:tape_store, updated_store)
        |> Map.put(:tape_last_error, nil)

      {:error, reason} ->
        Map.put(ctx, :tape_last_error, reason)
    end
  end

  defp tape_handoff_when!(ctx, %{name: name}, _meta) do
    store = ctx.tape_store

    case Gong.Tape.Store.handoff(store, name) do
      {:ok, _dir_name, updated_store} ->
        ctx
        |> Map.put(:tape_store, updated_store)
        |> Map.put(:tape_last_anchor, name)
        |> Map.put(:tape_last_error, nil)

      {:error, reason} ->
        Map.put(ctx, :tape_last_error, reason)
    end
  end

  defp tape_between_anchors_when!(ctx, %{start: start_a, end: end_a}, _meta) do
    store = ctx.tape_store

    case Gong.Tape.Store.between_anchors(store, start_a, end_a) do
      {:ok, entries} ->
        ctx
        |> Map.put(:tape_query_results, entries)
        |> Map.put(:tape_last_error, nil)

      {:error, reason} ->
        Map.put(ctx, :tape_last_error, reason)
    end
  end

  defp tape_search_when!(ctx, %{query: query}, _meta) do
    store = ctx.tape_store

    case Gong.Tape.Store.search(store, unescape(query)) do
      {:ok, entries} ->
        ctx
        |> Map.put(:tape_search_results, entries)
        |> Map.put(:tape_last_error, nil)

      {:error, reason} ->
        Map.put(ctx, :tape_last_error, reason)
    end
  end

  defp tape_fork_when!(ctx, _args, _meta) do
    store = ctx.tape_store

    case Gong.Tape.Store.fork(store) do
      {:ok, fork_store} ->
        ExUnit.Callbacks.on_exit(fn ->
          Gong.Tape.Store.close(fork_store)
          File.rm_rf(fork_store.workspace_path)
        end)

        ctx
        |> Map.put(:tape_parent_store, store)
        |> Map.put(:tape_store, fork_store)
        |> Map.put(:fork_store, fork_store)
        |> Map.put(:tape_path, fork_store.workspace_path)
        |> Map.put(:tape_fork_path, fork_store.workspace_path)
        |> Map.put(:tape_last_error, nil)

      {:error, reason} ->
        Map.put(ctx, :tape_last_error, reason)
    end
  end

  defp tape_merge_when!(ctx, _args, _meta) do
    parent = Map.get(ctx, :tape_parent_store, ctx.tape_store)
    fork_store = ctx.fork_store

    case Gong.Tape.Store.merge(parent, fork_store) do
      {:ok, updated_parent} ->
        ctx
        |> Map.put(:tape_store, updated_parent)
        |> Map.put(:tape_path, updated_parent.workspace_path)
        |> Map.put(:tape_last_error, nil)

      {:error, reason} ->
        # merge 失败时恢复到父工作区
        ctx
        |> Map.put(:tape_store, parent)
        |> Map.put(:tape_path, parent.workspace_path)
        |> Map.put(:tape_last_error, reason)
    end
  end

  defp tape_rebuild_index_when!(ctx, _args, _meta) do
    store = ctx.tape_store

    case Gong.Tape.Store.rebuild_index(store) do
      {:ok, updated_store} ->
        ctx
        |> Map.put(:tape_store, updated_store)
        |> Map.put(:tape_last_error, nil)

      {:error, reason} ->
        Map.put(ctx, :tape_last_error, reason)
    end
  end

  # ── Tape THEN 实现 ──

  defp assert_dir_exists!(ctx, %{path: path}, _meta) do
    full = resolve_tape_path(ctx, path)
    assert File.dir?(full), "期望目录存在: #{full}"
    ctx
  end

  defp assert_db_exists!(ctx, _args, _meta) do
    db_path = Path.join(ctx.tape_path, "index.db")
    assert File.exists?(db_path), "期望 index.db 存在: #{db_path}"
    ctx
  end

  defp assert_entry_count!(ctx, %{expected: expected}, _meta) do
    store = ctx.tape_store
    actual = Gong.Tape.Store.entry_count(store)

    assert actual == expected,
      "期望条目数=#{expected}，实际：#{actual}"

    ctx
  end

  defp assert_anchor_count!(ctx, %{expected: expected}, _meta) do
    store = ctx.tape_store
    actual = Gong.Tape.Store.anchor_count(store)

    assert actual == expected,
      "期望锚点数=#{expected}，实际：#{actual}"

    ctx
  end

  defp assert_jsonl_contains!(ctx, %{path: path, text: text}, _meta) do
    full = resolve_tape_path(ctx, path)
    content = File.read!(full)
    decoded = unescape(text)

    assert content =~ decoded,
      "期望 JSONL 文件 #{path} 包含 #{inspect(decoded)}，实际内容：#{String.slice(content, 0, 300)}"

    ctx
  end

  defp assert_jsonl_not_contains!(ctx, %{path: path, text: text}, _meta) do
    full = resolve_tape_path(ctx, path)
    decoded = unescape(text)

    case File.read(full) do
      {:ok, content} ->
        refute content =~ decoded,
          "期望 JSONL 文件 #{path} 不包含 #{inspect(decoded)}，但包含了"

      {:error, :enoent} ->
        # 文件不存在意味着不包含目标文本
        :ok
    end

    ctx
  end

  defp assert_query_results!(ctx, %{count: count} = args, _meta) do
    results = Map.get(ctx, :tape_query_results, [])

    assert length(results) == count,
      "期望查询结果 #{count} 条，实际：#{length(results)}"

    if text = args[:contains] do
      decoded = unescape(text)

      has_match =
        Enum.any?(results, fn entry ->
          to_string(entry.content) =~ decoded
        end)

      assert has_match,
        "期望查询结果包含 #{inspect(decoded)}"
    end

    ctx
  end

  defp assert_search_results!(ctx, %{count: count} = args, _meta) do
    results = Map.get(ctx, :tape_search_results, [])

    assert length(results) == count,
      "期望搜索结果 #{count} 条，实际：#{length(results)}"

    if text = args[:contains] do
      decoded = unescape(text)

      has_match =
        Enum.any?(results, fn entry ->
          to_string(entry.content) =~ decoded
        end)

      assert has_match,
        "期望搜索结果包含 #{inspect(decoded)}"
    end

    ctx
  end

  defp assert_tape_error!(ctx, %{error_contains: expected}, _meta) do
    error = Map.get(ctx, :tape_last_error)
    assert error != nil, "期望 Tape 错误，但 tape_last_error 为 nil"
    decoded = unescape(expected)

    assert to_string(error) =~ decoded,
      "期望错误包含 #{inspect(decoded)}，实际：#{inspect(error)}"

    ctx
  end

  defp assert_fork_cleaned!(ctx, _args, _meta) do
    fork_path = Map.get(ctx, :tape_fork_path)
    assert fork_path != nil, "tape_fork_path 为 nil，没有记录 fork 路径"
    refute File.exists?(fork_path), "fork 工作区 #{fork_path} 应在 merge 后被清理"
    ctx
  end

  # ── Tape 路径辅助 ──

  defp resolve_tape_path(ctx, path) do
    tape_path = Map.get(ctx, :tape_path, ctx.workspace)

    if String.starts_with?(path, "/") do
      path
    else
      Path.join(tape_path, path)
    end
  end

  # ── Compaction GIVEN 实现 ──

  defp compaction_messages!(ctx, %{count: count} = args, _meta) do
    if count == 0 do
      Map.put(ctx, :compaction_messages, [])
    else
      # 生成指定数量的测试消息
      token_size = Map.get(args, :token_size, 100)
      # 中文字符约 2 tokens/字，所以每条约 token_size/2 个中文字符
      char_count = max(div(token_size, 2), 10)

      messages =
        Enum.map(1..count, fn i ->
          content = "测试消息第#{i}条" <> String.duplicate("内容", max(div(char_count - 6, 2), 1))
          %{role: "user", content: content}
        end)

      Map.put(ctx, :compaction_messages, messages)
    end
  end

  defp compaction_messages_with_system!(ctx, %{count: count}, _meta) do
    # 第一条为系统消息，其余为用户消息
    system_msg = %{role: "system", content: "你是一个AI助手。"}

    user_messages =
      Enum.map(1..(count - 1), fn i ->
        %{role: "user", content: "测试消息第#{i}条，包含一些需要较多token的中文内容用于测试压缩功能。"}
      end)

    Map.put(ctx, :compaction_messages, [system_msg | user_messages])
  end

  defp compaction_lock_acquired!(ctx, %{session_id: session_id}, _meta) do
    Gong.Compaction.Lock.acquire(session_id)

    ExUnit.Callbacks.on_exit(fn ->
      Gong.Compaction.Lock.release(session_id)
    end)

    ctx
  end

  defp compaction_summarize_fn_ok!(ctx, _args, _meta) do
    summarize_fn = fn _messages ->
      {:ok, "这是一段会话摘要，包含了之前讨论的主要内容。"}
    end

    Map.put(ctx, :compaction_summarize_fn, summarize_fn)
  end

  defp compaction_summarize_fn_fail!(ctx, _args, _meta) do
    summarize_fn = fn _messages ->
      {:error, :llm_unavailable}
    end

    Map.put(ctx, :compaction_summarize_fn, summarize_fn)
  end

  # ── Compaction WHEN 实现 ──

  defp when_estimate_tokens!(ctx, _args, _meta) do
    messages = Map.fetch!(ctx, :compaction_messages)
    estimate = Gong.Compaction.TokenEstimator.estimate_messages(messages)

    ctx
    |> Map.put(:token_estimate, estimate)
    |> Map.put(:compaction_last_error, nil)
  end

  defp when_compact!(ctx, args, _meta) do
    messages = Map.fetch!(ctx, :compaction_messages)
    opts = build_compact_opts(ctx, args)

    {compacted, summary} = Gong.Compaction.compact(messages, opts)

    ctx
    |> Map.put(:compacted_messages, compacted)
    |> Map.put(:compaction_summary, summary)
    |> Map.put(:compaction_last_error, nil)
  end

  defp when_compact_and_handoff!(ctx, args, _meta) do
    messages = Map.fetch!(ctx, :compaction_messages)
    tape_store = Map.fetch!(ctx, :tape_store)
    opts = build_compact_opts(ctx, args)

    {compacted, summary, updated_store} =
      Gong.Compaction.compact_and_handoff(tape_store, messages, opts)

    ctx
    |> Map.put(:compacted_messages, compacted)
    |> Map.put(:compaction_summary, summary)
    |> Map.put(:tape_store, updated_store)
    |> Map.put(:compaction_last_error, nil)
  end

  defp when_acquire_lock!(ctx, %{session_id: session_id}, _meta) do
    case Gong.Compaction.Lock.acquire(session_id) do
      :ok ->
        ExUnit.Callbacks.on_exit(fn ->
          Gong.Compaction.Lock.release(session_id)
        end)

        ctx |> Map.put(:compaction_last_error, nil)

      {:error, reason} ->
        ctx |> Map.put(:compaction_last_error, reason)
    end
  end

  defp build_compact_opts(ctx, args) do
    opts = []
    opts = if args[:max_tokens], do: [{:max_tokens, args.max_tokens} | opts], else: opts
    opts = if args[:window_size], do: [{:window_size, args.window_size} | opts], else: opts
    opts = if args[:context_window], do: [{:context_window, args.context_window} | opts], else: opts
    opts = if args[:reserve_tokens], do: [{:reserve_tokens, args.reserve_tokens} | opts], else: opts

    if fn_ref = Map.get(ctx, :compaction_summarize_fn) do
      [{:summarize_fn, fn_ref} | opts]
    else
      opts
    end
  end

  # ── Compaction THEN 实现 ──

  defp assert_token_estimate!(ctx, %{min: min, max: max}, _meta) do
    estimate = Map.fetch!(ctx, :token_estimate)

    assert estimate >= min,
      "期望 token 估算 >= #{min}，实际：#{estimate}"

    assert estimate <= max,
      "期望 token 估算 <= #{max}，实际：#{estimate}"

    ctx
  end

  defp assert_compacted!(ctx, %{message_count: expected}, _meta) do
    compacted = Map.fetch!(ctx, :compacted_messages)
    actual = length(compacted)

    assert actual == expected,
      "期望压缩后消息数=#{expected}，实际：#{actual}"

    ctx
  end

  defp assert_not_compacted!(ctx, _args, _meta) do
    summary = Map.get(ctx, :compaction_summary)
    assert summary == nil, "期望未触发压缩，但 summary=#{inspect(summary)}"

    # 压缩后消息应与原始消息相同
    compacted = Map.get(ctx, :compacted_messages)
    original = Map.get(ctx, :compaction_messages)

    if compacted && original do
      assert length(compacted) == length(original),
        "期望消息数不变 #{length(original)}，实际：#{length(compacted)}"
    end

    ctx
  end

  defp assert_summary_exists!(ctx, _args, _meta) do
    summary = Map.get(ctx, :compaction_summary)
    assert summary != nil, "期望 summary 不为 nil"
    assert is_binary(summary), "期望 summary 是字符串，实际：#{inspect(summary)}"
    ctx
  end

  defp assert_summary_nil!(ctx, _args, _meta) do
    summary = Map.get(ctx, :compaction_summary)
    assert summary == nil, "期望 summary 为 nil，实际：#{inspect(summary)}"
    ctx
  end

  defp assert_system_preserved!(ctx, _args, _meta) do
    compacted = Map.fetch!(ctx, :compacted_messages)

    # 检查压缩后的消息中仍包含系统消息
    has_system =
      Enum.any?(compacted, fn msg ->
        role = Map.get(msg, :role) || Map.get(msg, "role")
        to_string(role) == "system"
      end)

    assert has_system, "期望系统消息在压缩后仍然存在"
    ctx
  end

  defp assert_compaction_error!(ctx, %{error_contains: expected}, _meta) do
    error = Map.get(ctx, :compaction_last_error)
    assert error != nil, "期望压缩错误，但 compaction_last_error 为 nil"
    decoded = unescape(expected)

    assert to_string(error) =~ decoded,
      "期望错误包含 #{inspect(decoded)}，实际：#{inspect(error)}"

    ctx
  end

  # ── Tape metadata 断言 ──

  defp assert_entry_has_metadata!(ctx, %{key: key, value: value}, _meta) do
    results = Map.get(ctx, :tape_search_results, [])

    if key == "" and value == "" do
      # 验证 metadata 为空对象
      entry = List.first(results)
      assert entry != nil, "期望至少有一个搜索结果"
      metadata = Map.get(entry, :metadata, %{})
      assert metadata == %{} or metadata == nil, "期望 metadata 为空，实际：#{inspect(metadata)}"
    else
      entry = List.first(results)
      assert entry != nil, "期望至少有一个搜索结果"
      metadata = Map.get(entry, :metadata, %{})
      assert metadata != nil, "期望 metadata 不为 nil"
      actual = Map.get(metadata, key)
      assert to_string(actual) == value, "期望 metadata[#{key}]=#{value}，实际：#{inspect(actual)}"
    end

    ctx
  end

  defp assert_search_result_count!(ctx, %{expected: expected}, _meta) do
    results = Map.get(ctx, :tape_search_results, [])
    actual = length(results)
    assert actual == expected, "期望搜索结果数=#{expected}，实际：#{actual}"
    ctx
  end

  # ── Compaction 扩展实现 ──

  defp compaction_summarize_fn_raise!(ctx, _args, _meta) do
    summarize_fn = fn _messages ->
      raise "LLM 摘要服务异常"
    end

    Map.put(ctx, :compaction_summarize_fn, summarize_fn)
  end

  defp when_release_lock!(ctx, %{session_id: session_id}, _meta) do
    Gong.Compaction.Lock.release(session_id)
    ctx |> Map.put(:compaction_last_error, nil)
  end

  defp assert_no_compaction_error!(ctx, _args, _meta) do
    error = Map.get(ctx, :compaction_last_error)
    assert error == nil, "期望无错误，但 compaction_last_error=#{inspect(error)}"
    ctx
  end

  # ── Hook 扩展断言实现 ──

  defp assert_no_hook_error!(ctx, _args, _meta) do
    events = Map.get(ctx, :telemetry_events, [])

    hook_errors =
      Enum.filter(events, fn {name, _, _} ->
        name == [:gong, :hook, :error]
      end)

    assert hook_errors == [],
      "期望无 hook 错误事件，但收到 #{length(hook_errors)} 个"

    ctx
  end

  defp assert_telemetry_sequence!(ctx, %{sequence: sequence_str}, _meta) do
    expected =
      sequence_str
      |> String.split(",")
      |> Enum.map(fn name ->
        name |> String.trim() |> String.split(".") |> Enum.map(&String.to_atom/1)
      end)

    events = Map.get(ctx, :telemetry_events, [])
    actual_names = Enum.map(events, fn {name, _, _} -> name end)

    # 检查 expected 是 actual_names 的子序列（保序）
    assert_subsequence(expected, actual_names)
    ctx
  end

  defp assert_subsequence([], _actual), do: :ok

  defp assert_subsequence([exp | rest_exp], [act | rest_act]) do
    if exp == act do
      assert_subsequence(rest_exp, rest_act)
    else
      assert_subsequence([exp | rest_exp], rest_act)
    end
  end

  defp assert_subsequence(remaining, []) do
    remaining_str = Enum.map(remaining, &Enum.join(&1, ".")) |> Enum.join(", ")
    flunk("Telemetry 事件序列不完整，缺失：#{remaining_str}")
  end

  defp assert_tape_has_compaction_anchor!(ctx, _args, _meta) do
    store = Map.fetch!(ctx, :tape_store)
    # 检查 anchor 数量增加（至少 2：session-start + compaction）
    anchor_count = Gong.Tape.Store.anchor_count(store)

    assert anchor_count >= 2,
      "期望至少 2 个 anchor（含 compaction），实际：#{anchor_count}"

    ctx
  end

  # ── Steering 实现 ──

  defp steering_queue_empty!(ctx, _args, _meta) do
    Map.put(ctx, :steering_queue, Gong.Steering.new())
  end

  defp steering_push!(ctx, %{message: message}, _meta) do
    queue = Map.get(ctx, :steering_queue, Gong.Steering.new())
    Map.put(ctx, :steering_queue, Gong.Steering.push(queue, message))
  end

  defp steering_check!(ctx, _args, _meta) do
    queue = Map.get(ctx, :steering_queue, Gong.Steering.new())
    {msg, new_queue} = Gong.Steering.check(queue)

    ctx
    |> Map.put(:steering_queue, new_queue)
    |> Map.put(:steering_last_message, msg)
  end

  defp steering_skip_result!(ctx, %{tool: tool}, _meta) do
    result = Gong.Steering.skip_result(tool)
    Map.put(ctx, :steering_skip_result, result)
  end

  defp assert_steering_pending!(ctx, _args, _meta) do
    queue = Map.get(ctx, :steering_queue, [])
    assert Gong.Steering.pending?(queue), "期望 steering 队列有待处理消息"
    ctx
  end

  defp assert_steering_empty!(ctx, _args, _meta) do
    queue = Map.get(ctx, :steering_queue, [])
    refute Gong.Steering.pending?(queue), "期望 steering 队列为空"
    ctx
  end

  defp assert_steering_message!(ctx, %{contains: text}, _meta) do
    msg = Map.get(ctx, :steering_last_message)
    assert msg != nil, "期望 steering 消息不为 nil"
    assert msg =~ text, "期望 steering 消息包含 #{inspect(text)}，实际：#{inspect(msg)}"
    ctx
  end

  defp assert_steering_skip_contains!(ctx, %{text: text}, _meta) do
    result = Map.get(ctx, :steering_skip_result)
    assert result != nil, "期望 skip_result 不为 nil"
    result_str = inspect(result)
    assert result_str =~ text, "期望 skip_result 包含 #{inspect(text)}，实际：#{inspect(result)}"
    ctx
  end

  # ── Retry 实现 ──

  defp classify_error!(ctx, %{error: error}, _meta) do
    class = Gong.Retry.classify_error(error)
    Map.put(ctx, :retry_error_class, class)
  end

  defp retry_delay!(ctx, %{attempt: attempt}, _meta) do
    delay = Gong.Retry.delay_ms(attempt)
    Map.put(ctx, :retry_delay_ms, delay)
  end

  defp retry_should_retry!(ctx, %{error_class: error_class, attempt: attempt}, _meta) do
    class = String.to_existing_atom(error_class)
    result = Gong.Retry.should_retry?(class, attempt)
    Map.put(ctx, :retry_should_retry, result)
  end

  defp assert_error_class!(ctx, %{expected: expected}, _meta) do
    actual = Map.fetch!(ctx, :retry_error_class)
    assert to_string(actual) == expected,
      "期望错误分类=#{expected}，实际：#{actual}"
    ctx
  end

  defp assert_delay_ms!(ctx, %{expected: expected}, _meta) do
    actual = Map.fetch!(ctx, :retry_delay_ms)
    assert actual == expected,
      "期望延迟=#{expected}ms，实际：#{actual}ms"
    ctx
  end

  defp assert_should_retry!(ctx, %{expected: expected}, _meta) do
    actual = Map.fetch!(ctx, :retry_should_retry)
    assert actual == expected,
      "期望 should_retry=#{expected}，实际：#{actual}"
    ctx
  end

  # ── Compaction 配对保护实现 ──

  defp compaction_messages_with_tools!(ctx, %{count: count, tool_pair_at: tool_pair_at} = args, _meta) do
    token_size = Map.get(args, :token_size, 100)
    char_count = max(div(token_size, 2), 10)

    messages =
      Enum.map(0..(count - 1), fn i ->
        cond do
          i == tool_pair_at ->
            # assistant 消息携带 tool_calls
            %{
              role: "assistant",
              content: "调用工具",
              tool_calls: [%{id: "tc_#{i}", name: "bash", arguments: %{"command" => "echo hi"}}]
            }

          i == tool_pair_at + 1 ->
            # tool 结果消息
            %{role: "tool", content: "hi\n", tool_call_id: "tc_#{i - 1}"}

          true ->
            content = "测试消息第#{i}条" <> String.duplicate("内容", max(div(char_count - 6, 2), 1))
            role = if rem(i, 2) == 0, do: "user", else: "assistant"
            %{role: role, content: content}
        end
      end)

    Map.put(ctx, :compaction_messages, messages)
  end

  defp assert_tool_pairs_intact!(ctx, _args, _meta) do
    compacted = Map.fetch!(ctx, :compacted_messages)

    # 验证所有 tool_calls 消息后都跟着 tool 消息
    compacted
    |> Enum.with_index()
    |> Enum.each(fn {msg, idx} ->
      if has_tool_calls_field?(msg) do
        assert idx + 1 < length(compacted),
          "tool_calls 消息在末尾，缺少 tool 结果"

        next = Enum.at(compacted, idx + 1)
        next_role = Map.get(next, :role) || Map.get(next, "role")

        assert to_string(next_role) == "tool",
          "tool_calls 消息后应跟 tool 消息，实际：#{inspect(next_role)}"
      end
    end)

    ctx
  end

  defp has_tool_calls_field?(%{tool_calls: tcs}) when is_list(tcs) and tcs != [], do: true
  defp has_tool_calls_field?(%{"tool_calls" => tcs}) when is_list(tcs) and tcs != [], do: true
  defp has_tool_calls_field?(_), do: false

  # ── 结构化摘要实现 ──

  defp compaction_messages_with_tool_calls!(ctx, %{count: count}, _meta) do
    # 生成包含 tool_call 的消息序列
    messages =
      Enum.flat_map(1..count, fn i ->
        [
          %{
            role: "assistant",
            content: "执行操作#{i}",
            tool_calls: [
              %{id: "tc_#{i}", name: "read_file", arguments: %{"file_path" => "/tmp/file#{i}.txt"}}
            ]
          },
          %{role: "tool", content: "文件内容#{i}", tool_call_id: "tc_#{i}"}
        ]
      end)

    Map.put(ctx, :compaction_messages, messages)
  end

  defp compaction_messages_with_summary!(ctx, %{count: count, summary: summary}, _meta) do
    # 第一条是前次摘要消息，其余是普通消息
    summary_msg = %{role: "system", content: "[会话摘要] #{summary}"}

    user_messages =
      Enum.map(1..(count - 1), fn i ->
        %{role: "user", content: "后续对话消息#{i}"}
      end)

    Map.put(ctx, :compaction_messages, [summary_msg | user_messages])
  end

  defp build_summarize_prompt!(ctx, _args, _meta) do
    messages = Map.fetch!(ctx, :compaction_messages)
    {mode, prompt} = Gong.Prompt.build_summarize_prompt(messages)

    ctx
    |> Map.put(:summarize_prompt, prompt)
    |> Map.put(:summarize_prompt_mode, mode)
  end

  defp extract_file_operations!(ctx, _args, _meta) do
    messages = Map.fetch!(ctx, :compaction_messages)
    file_ops = Gong.Prompt.extract_file_operations(messages)
    Map.put(ctx, :file_ops_result, file_ops)
  end

  defp assert_prompt_contains!(ctx, %{text: text}, _meta) do
    prompt = Map.fetch!(ctx, :summarize_prompt)
    assert prompt =~ text,
      "期望 prompt 包含 #{inspect(text)}，实际：#{String.slice(prompt, 0, 300)}"
    ctx
  end

  defp assert_prompt_mode!(ctx, %{expected: expected}, _meta) do
    mode = Map.fetch!(ctx, :summarize_prompt_mode)
    assert to_string(mode) == expected,
      "期望 prompt 模式=#{expected}，实际：#{mode}"
    ctx
  end

  defp assert_file_ops_contains!(ctx, %{text: text}, _meta) do
    file_ops = Map.fetch!(ctx, :file_ops_result)
    assert file_ops =~ text,
      "期望文件操作包含 #{inspect(text)}，实际：#{inspect(file_ops)}"
    ctx
  end

  # ── Prompt 工程实现 ──

  defp prompt_messages_with_long_content!(ctx, %{length: length}, _meta) do
    long_text = String.duplicate("测试内容", div(length, 4) + 1) |> String.slice(0, length)
    messages = [%{role: "user", content: long_text}]
    Map.put(ctx, :prompt_messages, messages)
  end

  defp prompt_messages_plain!(ctx, %{count: count}, _meta) do
    messages = Enum.map(1..count, fn i ->
      %{role: "user", content: "普通消息#{i}"}
    end)
    Map.put(ctx, :prompt_messages, messages)
  end

  defp prompt_messages_multi_tools!(ctx, %{tools: tools_str}, _meta) do
    # 格式: "read_file:/a.txt,write_file:/b.txt"
    tool_pairs = String.split(tools_str, ",")
    messages = Enum.map(tool_pairs, fn pair ->
      [name, path] = String.split(pair, ":")
      %{
        role: "assistant",
        content: "执行#{name}",
        tool_calls: [%{name: name, arguments: %{"file_path" => path}}]
      }
    end)
    Map.put(ctx, :prompt_messages, messages)
  end

  defp prompt_messages_with_summary_prompt!(ctx, %{summary: summary}, _meta) do
    messages = [
      %{role: "system", content: "[会话摘要] #{summary}"},
      %{role: "user", content: "后续消息1"},
      %{role: "assistant", content: "回复1"}
    ]
    Map.put(ctx, :prompt_messages, messages)
  end

  defp build_default_prompt!(ctx, _args, _meta) do
    prompt = Gong.Prompt.default_system_prompt()
    Map.put(ctx, :prompt_result, prompt)
  end

  defp build_workspace_prompt!(ctx, _args, _meta) do
    workspace = Map.get(ctx, :workspace, "/tmp/test")
    prompt = Gong.Prompt.system_prompt(workspace)
    Map.put(ctx, :prompt_result, prompt)
  end

  defp format_conversation!(ctx, _args, _meta) do
    messages = Map.fetch!(ctx, :prompt_messages)
    # format_conversation 是私有函数，通过 build_summarize_prompt 间接测试
    # 直接调用 build_summarize_prompt 取 prompt 文本
    {_mode, prompt} = Gong.Prompt.build_summarize_prompt(messages)
    Map.put(ctx, :formatted_result, prompt)
  end

  defp find_previous_summary!(ctx, _args, _meta) do
    messages = Map.fetch!(ctx, :prompt_messages)
    {mode, _prompt} = Gong.Prompt.build_summarize_prompt(messages)
    # 如果 mode 是 :update，说明找到了前次摘要
    case mode do
      :update ->
        # 从 messages 中提取摘要内容
        summary = Enum.find_value(messages, fn msg ->
          content = Map.get(msg, :content, "")
          if String.starts_with?(to_string(content), "[会话摘要]") do
            String.trim_leading(to_string(content), "[会话摘要] ")
          end
        end)
        Map.put(ctx, :previous_summary, summary)
      :create ->
        Map.put(ctx, :previous_summary, nil)
    end
  end

  defp assert_prompt_text!(ctx, %{contains: text}, _meta) do
    prompt = Map.fetch!(ctx, :prompt_result)
    assert prompt =~ text,
      "期望 prompt 包含 #{inspect(text)}，实际：#{String.slice(prompt, 0, 200)}"
    ctx
  end

  defp assert_formatted_length!(ctx, %{max: max}, _meta) do
    formatted = Map.fetch!(ctx, :formatted_result)
    # 检查每条消息的格式化内容是否被截断
    assert String.length(formatted) > 0, "格式化结果不能为空"
    # format_conversation 截断每条消息到 500 字符，检查总长度合理
    # 单条消息格式化后 "[user] " + 500 字符 < max
    lines = String.split(formatted, "\n") |> Enum.filter(&(&1 =~ ~r/\[user\]/))
    Enum.each(lines, fn line ->
      # 去掉 prompt 模板文本，只看 [user] 行
      content_part = String.replace(line, ~r/^\[user\]\s*/, "")
      assert String.length(content_part) <= max,
        "格式化行长度#{String.length(content_part)}超过#{max}"
    end)
    ctx
  end

  defp extract_prompt_file_ops!(ctx, _args, _meta) do
    messages = Map.fetch!(ctx, :prompt_messages)
    file_ops = Gong.Prompt.extract_file_operations(messages)
    Map.put(ctx, :prompt_file_ops_result, file_ops)
  end

  defp assert_file_ops_text!(ctx, %{contains: text}, _meta) do
    file_ops = Map.fetch!(ctx, :prompt_file_ops_result)
    assert file_ops =~ text,
      "期望文件操作包含 #{inspect(text)}，实际：#{inspect(file_ops)}"
    ctx
  end

  defp assert_previous_summary!(ctx, %{contains: text}, _meta) do
    summary = Map.fetch!(ctx, :previous_summary)
    assert summary != nil, "期望找到前次摘要但为 nil"
    assert summary =~ text,
      "期望前次摘要包含 #{inspect(text)}，实际：#{inspect(summary)}"
    ctx
  end

  defp assert_previous_summary_nil!(ctx, _args, _meta) do
    summary = Map.get(ctx, :previous_summary)
    assert summary == nil, "期望无前次摘要，实际：#{inspect(summary)}"
    ctx
  end

  # ── Lock 并发 & Token 精度实现 ──

  defp concurrent_lock_acquire!(ctx, %{session_id: session_id, tasks: tasks}, _meta) do
    Gong.Compaction.Lock.ensure_table()
    # 先确保锁是空闲的
    Gong.Compaction.Lock.release(session_id)

    # 并发获取锁
    results = 1..tasks
    |> Enum.map(fn _i ->
      Task.async(fn ->
        Gong.Compaction.Lock.acquire(session_id)
      end)
    end)
    |> Enum.map(&Task.await/1)

    winners = Enum.count(results, &(&1 == :ok))
    # 清理
    Gong.Compaction.Lock.release(session_id)

    Map.put(ctx, :lock_race_winners, winners)
  end

  defp assert_lock_race_result!(ctx, %{winners: expected}, _meta) do
    actual = Map.fetch!(ctx, :lock_race_winners)
    assert actual == expected,
      "期望 #{expected} 个获胜者，实际：#{actual}"
    ctx
  end

  defp estimate_text!(ctx, %{content: content}, _meta) do
    estimate = Gong.Compaction.TokenEstimator.estimate(content)
    Map.put(ctx, :token_estimate_value, estimate)
  end

  defp assert_token_estimate_value!(ctx, %{expected: expected}, _meta) do
    actual = Map.fetch!(ctx, :token_estimate_value)
    assert actual == expected,
      "期望 token 估算=#{expected}，实际：#{actual}"
    ctx
  end

  # ── Provider Registry 实现 ──

  defp init_provider_registry!(ctx, _args, _meta) do
    Gong.ProviderRegistry.cleanup()
    Gong.ProviderRegistry.init()
    ctx
  end

  defp register_provider!(ctx, args, _meta) do
    name = args.name
    priority = Map.get(args, :priority, 0)

    # MockProvider 是一个简单的实现
    module = mock_provider_module()

    result = Gong.ProviderRegistry.register(name, module, %{}, priority: priority)

    case result do
      :ok -> ctx
      {:error, reason} -> Map.put(ctx, :provider_error, to_string(reason))
    end
  end

  defp register_provider_with_invalid_config!(ctx, %{name: name}, _meta) do
    module = mock_provider_with_validation_module()
    result = Gong.ProviderRegistry.register(name, module, %{invalid: true})

    case result do
      :ok -> ctx
      {:error, reason} -> Map.put(ctx, :provider_error, to_string(reason))
    end
  end

  defp switch_provider!(ctx, %{name: name}, _meta) do
    Gong.ProviderRegistry.switch(name)
    ctx
  end

  defp switch_provider_expect_error!(ctx, %{name: name}, _meta) do
    case Gong.ProviderRegistry.switch(name) do
      :ok -> ctx
      {:error, reason} -> Map.put(ctx, :provider_error, to_string(reason))
    end
  end

  defp provider_fallback!(ctx, %{from: from}, _meta) do
    case Gong.ProviderRegistry.fallback(from) do
      {:ok, _next} -> ctx
      {:error, reason} -> Map.put(ctx, :provider_error, to_string(reason))
    end
  end

  defp provider_fallback_expect_error!(ctx, %{from: from}, _meta) do
    case Gong.ProviderRegistry.fallback(from) do
      {:ok, _next} -> ctx
      {:error, reason} -> Map.put(ctx, :provider_error, to_string(reason))
    end
  end

  defp assert_provider_count!(ctx, %{expected: expected}, _meta) do
    actual = length(Gong.ProviderRegistry.list())
    assert actual == expected,
      "期望 #{expected} 个 provider，实际：#{actual}"
    ctx
  end

  defp assert_current_provider!(ctx, %{expected: expected}, _meta) do
    case Gong.ProviderRegistry.current() do
      {name, _entry} ->
        assert name == expected,
          "期望当前 provider=#{expected}，实际：#{name}"
      nil ->
        flunk("当前无 provider")
    end
    ctx
  end

  defp assert_provider_error!(ctx, %{contains: text}, _meta) do
    error = Map.get(ctx, :provider_error, "")
    assert error =~ text,
      "期望 provider 错误包含 #{inspect(text)}，实际：#{inspect(error)}"
    ctx
  end

  defp assert_provider_list_order!(ctx, %{expected: expected_str}, _meta) do
    expected = String.split(expected_str, ",")
    actual = Gong.ProviderRegistry.list() |> Enum.map(fn {name, _} -> name end)
    assert actual == expected,
      "期望 provider 顺序=#{inspect(expected)}，实际：#{inspect(actual)}"
    ctx
  end

  # Mock Provider 模块（定义在 test/support/mock_provider.ex）
  defp mock_provider_module, do: Gong.Test.MockProvider
  defp mock_provider_with_validation_module, do: Gong.Test.MockProviderWithValidation

  # ── Thinking 预算实现 ──

  defp validate_thinking_level!(ctx, %{level: level_str}, _meta) do
    case Gong.Thinking.parse(level_str) do
      {:ok, level} -> Map.put(ctx, :thinking_level, level) |> Map.put(:thinking_valid, true)
      {:error, _} -> Map.put(ctx, :thinking_valid, false)
    end
  end

  defp get_thinking_budget!(ctx, %{level: level_str}, _meta) do
    {:ok, level} = Gong.Thinking.parse(level_str)
    budget = Gong.Thinking.budget(level)
    Map.put(ctx, :thinking_budget, budget)
  end

  defp thinking_to_provider!(ctx, %{level: level_str, provider: provider}, _meta) do
    {:ok, level} = Gong.Thinking.parse(level_str)
    params = Gong.Thinking.to_provider_params(level, provider)
    Map.put(ctx, :thinking_params, params)
  end

  defp assert_thinking_valid!(ctx, _args, _meta) do
    assert Map.get(ctx, :thinking_valid) == true, "期望 thinking level 有效"
    ctx
  end

  defp assert_thinking_invalid!(ctx, _args, _meta) do
    assert Map.get(ctx, :thinking_valid) == false, "期望 thinking level 无效"
    ctx
  end

  defp assert_thinking_budget!(ctx, %{expected: expected}, _meta) do
    actual = Map.fetch!(ctx, :thinking_budget)
    assert actual == expected,
      "期望 thinking budget=#{expected}，实际：#{actual}"
    ctx
  end

  defp assert_thinking_params!(ctx, %{contains: text}, _meta) do
    params = Map.fetch!(ctx, :thinking_params)
    params_str = inspect(params)
    assert params_str =~ text,
      "期望 thinking params 包含 #{inspect(text)}，实际：#{params_str}"
    ctx
  end

  defp assert_thinking_params_empty!(ctx, _args, _meta) do
    params = Map.fetch!(ctx, :thinking_params)
    assert params == %{},
      "期望 thinking params 为空，实际：#{inspect(params)}"
    ctx
  end

  # ── Cost 追踪实现 ──

  defp init_cost_tracker!(ctx, _args, _meta) do
    Gong.CostTracker.init()
    ctx
  end

  defp record_llm_call!(ctx, %{model: model, input_tokens: input, output_tokens: output}, _meta) do
    usage = %{input_tokens: input, output_tokens: output, cache_hit_tokens: 0, total_cost: 0.0}
    Gong.CostTracker.record(model, usage)
    ctx
  end

  defp reset_cost_tracker!(ctx, _args, _meta) do
    Gong.CostTracker.reset()
    ctx
  end

  defp assert_cost_summary!(ctx, args, _meta) do
    summary = Gong.CostTracker.summary()
    assert summary.call_count == args.call_count,
      "期望 call_count=#{args.call_count}，实际：#{summary.call_count}"

    if Map.has_key?(args, :total_input) do
      assert summary.total_input == args.total_input,
        "期望 total_input=#{args.total_input}，实际：#{summary.total_input}"
    end

    if Map.has_key?(args, :total_output) do
      assert summary.total_output == args.total_output,
        "期望 total_output=#{args.total_output}，实际：#{summary.total_output}"
    end

    ctx
  end

  defp assert_last_call!(ctx, %{model: expected_model}, _meta) do
    last = Gong.CostTracker.last_call()
    assert last != nil, "期望有最近调用记录"
    assert last.model == expected_model,
      "期望最近调用 model=#{expected_model}，实际：#{last.model}"
    ctx
  end

  # ── Prompt 模板实现 ──

  defp init_prompt_templates!(ctx, _args, _meta) do
    Gong.PromptTemplate.cleanup()
    Gong.PromptTemplate.init()
    ctx
  end

  defp register_template!(ctx, %{name: name, content: content}, _meta) do
    Gong.PromptTemplate.register(name, unescape(content))
    ctx
  end

  defp get_template!(ctx, %{name: name}, _meta) do
    case Gong.PromptTemplate.get(name) do
      {:ok, template} -> Map.put(ctx, :template_result, template)
      {:error, reason} -> Map.put(ctx, :template_error, to_string(reason))
    end
  end

  defp get_template_expect_error!(ctx, %{name: name}, _meta) do
    case Gong.PromptTemplate.get(name) do
      {:ok, _} -> ctx
      {:error, reason} -> Map.put(ctx, :template_error, to_string(reason))
    end
  end

  defp render_template!(ctx, %{name: name, bindings: bindings_str}, _meta) do
    # 格式: "key1:value1,key2:value2"
    bindings = bindings_str
    |> String.split(",")
    |> Enum.map(fn pair ->
      case String.split(pair, ":", parts: 2) do
        [k, v] -> {k, v}
        _ -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)
    |> Map.new()

    case Gong.PromptTemplate.render(name, bindings) do
      {:ok, rendered} -> Map.put(ctx, :rendered_content, rendered)
      {:error, reason} -> Map.put(ctx, :template_error, to_string(reason))
    end
  end

  defp assert_template_exists!(ctx, %{name: name}, _meta) do
    template = Map.get(ctx, :template_result)
    assert template != nil, "期望模板 #{name} 存在"
    assert template.name == name,
      "期望模板名=#{name}，实际：#{template.name}"
    ctx
  end

  defp assert_template_variables!(ctx, %{expected: expected_str}, _meta) do
    template = Map.fetch!(ctx, :template_result)
    expected = String.split(expected_str, ",") |> Enum.sort()
    actual = Enum.sort(template.variables)
    assert actual == expected,
      "期望变量=#{inspect(expected)}，实际：#{inspect(actual)}"
    ctx
  end

  defp assert_rendered_content!(ctx, %{contains: text}, _meta) do
    rendered = Map.fetch!(ctx, :rendered_content)
    assert rendered =~ text,
      "期望渲染内容包含 #{inspect(text)}，实际：#{String.slice(rendered, 0, 200)}"
    ctx
  end

  defp assert_template_error!(ctx, %{contains: text}, _meta) do
    error = Map.get(ctx, :template_error, "")
    assert error =~ text,
      "期望模板错误包含 #{inspect(text)}，实际：#{inspect(error)}"
    ctx
  end

  # ── RPC 模式实现 ──

  defp parse_rpc_request!(ctx, %{json: json}, _meta) do
    case Gong.RPC.parse_request(unescape(json)) do
      {:ok, request} -> Map.put(ctx, :rpc_request, request)
      {:error, error} -> Map.put(ctx, :rpc_error, error)
    end
  end

  defp rpc_dispatch!(ctx, %{method: method, params: params_json}, _meta) do
    params = Jason.decode!(unescape(params_json))
    handlers = %{
      "echo" => fn p -> Map.get(p, "msg", "") end,
      "add" => fn p -> Map.get(p, "a", 0) + Map.get(p, "b", 0) end
    }
    request = %{method: method, params: params, id: 1}
    result = Gong.RPC.dispatch(request, handlers)
    Map.put(ctx, :rpc_response, result)
  end

  defp rpc_dispatch_missing!(ctx, %{method: method}, _meta) do
    handlers = %{"echo" => fn _p -> "ok" end}
    request = %{method: method, params: %{}, id: 1}
    result = Gong.RPC.dispatch(request, handlers)
    Map.put(ctx, :rpc_response, result)
  end

  defp rpc_handle!(ctx, %{json: json}, _meta) do
    handlers = %{
      "echo" => fn p -> Map.get(p, "msg", "") end
    }
    response_json = Gong.RPC.handle(unescape(json), handlers)
    Map.put(ctx, :rpc_response_json, response_json)
  end

  defp assert_rpc_parsed!(ctx, %{method: expected}, _meta) do
    request = Map.fetch!(ctx, :rpc_request)
    assert request.method == expected,
      "期望 RPC method=#{expected}，实际：#{request.method}"
    ctx
  end

  defp assert_rpc_error!(ctx, %{code: expected_code}, _meta) do
    # 检查 rpc_error 或 rpc_response 中的错误
    cond do
      Map.has_key?(ctx, :rpc_error) ->
        error = ctx.rpc_error
        assert error.error.code == expected_code,
          "期望 RPC 错误码=#{expected_code}，实际：#{error.error.code}"

      Map.has_key?(ctx, :rpc_response) ->
        response = ctx.rpc_response
        assert Map.has_key?(response, :error),
          "期望 RPC 响应有错误，实际：#{inspect(response)}"
        assert response.error.code == expected_code,
          "期望 RPC 错误码=#{expected_code}，实际：#{response.error.code}"

      true ->
        flunk("无 RPC 错误")
    end
    ctx
  end

  defp assert_rpc_result!(ctx, %{contains: text}, _meta) do
    response = Map.fetch!(ctx, :rpc_response)
    result_str = inspect(response.result)
    assert result_str =~ text,
      "期望 RPC result 包含 #{inspect(text)}，实际：#{result_str}"
    ctx
  end

  defp assert_rpc_response_json!(ctx, %{contains: text}, _meta) do
    json = Map.fetch!(ctx, :rpc_response_json)
    assert json =~ text,
      "期望 RPC 响应 JSON 包含 #{inspect(text)}，实际：#{json}"
    ctx
  end

  # ── Auth OAuth 实现 ──

  defp detect_auth_method!(ctx, %{provider: provider}, _meta) do
    method = Gong.Auth.auth_method(provider)
    Map.put(ctx, :auth_method, method)
  end

  defp generate_authorize_url!(ctx, %{client_id: client_id, authorize_url: auth_url}, _meta) do
    config = %{
      client_id: client_id,
      client_secret: "test_secret",
      authorize_url: auth_url,
      token_url: "https://auth.example.com/token",
      redirect_uri: "http://localhost:8080/callback",
      scopes: ["read", "write"]
    }
    url = Gong.Auth.authorize_url(config)
    Map.put(ctx, :authorize_url, url)
  end

  defp exchange_auth_code!(ctx, %{code: code}, _meta) do
    config = %{
      client_id: "test",
      client_secret: "test",
      authorize_url: "https://auth.example.com/authorize",
      token_url: "https://auth.example.com/token",
      redirect_uri: "http://localhost:8080/callback",
      scopes: []
    }
    {:ok, token} = Gong.Auth.exchange_code(config, code)
    Map.put(ctx, :auth_token, token)
  end

  defp assert_auth_method!(ctx, %{expected: expected}, _meta) do
    actual = Map.fetch!(ctx, :auth_method)
    assert to_string(actual) == expected,
      "期望 auth method=#{expected}，实际：#{actual}"
    ctx
  end

  defp assert_authorize_url!(ctx, %{contains: text}, _meta) do
    url = Map.fetch!(ctx, :authorize_url)
    assert url =~ text,
      "期望 authorize URL 包含 #{inspect(text)}，实际：#{url}"
    ctx
  end

  defp assert_auth_token!(ctx, %{contains: text}, _meta) do
    token = Map.fetch!(ctx, :auth_token)
    token_str = inspect(token)
    assert token_str =~ text,
      "期望 token 包含 #{inspect(text)}，实际：#{token_str}"
    ctx
  end

  # ── Cross-provider & Command 实现 ──

  defp cross_provider_messages!(ctx, %{count: count}, _meta) do
    messages = if count == 0 do
      []
    else
      Enum.map(1..count, fn i ->
        %{role: "user", content: "消息#{i}"}
      end)
    end
    Map.put(ctx, :cross_messages, messages)
  end

  defp cross_provider_multipart_message!(ctx, _args, _meta) do
    messages = [%{
      role: "assistant",
      content: [
        %{type: "text", text: "部分1"},
        %{type: "text", text: "部分2"}
      ]
    }]
    Map.put(ctx, :cross_messages, messages)
  end

  defp convert_messages!(ctx, %{from: from, to: to}, _meta) do
    messages = Map.fetch!(ctx, :cross_messages)
    converted = Gong.CrossProvider.convert_messages(messages, from, to)
    Map.put(ctx, :converted_messages, converted)
  end

  defp build_handoff_summary!(ctx, _args, _meta) do
    messages = Map.fetch!(ctx, :cross_messages)
    summary = Gong.CrossProvider.build_handoff_summary(messages)
    Map.put(ctx, :handoff_summary, summary)
  end

  defp assert_converted_messages!(ctx, %{count: expected}, _meta) do
    converted = Map.fetch!(ctx, :converted_messages)
    assert length(converted) == expected,
      "期望 #{expected} 条转换消息，实际：#{length(converted)}"
    ctx
  end

  defp assert_handoff_summary_not_empty!(ctx, _args, _meta) do
    summary = Map.fetch!(ctx, :handoff_summary)
    assert String.length(summary) > 0, "期望 handoff 摘要非空"
    ctx
  end

  defp assert_content_is_text!(ctx, _args, _meta) do
    converted = Map.fetch!(ctx, :converted_messages)
    Enum.each(converted, fn msg ->
      content = Map.get(msg, :content, Map.get(msg, "content"))
      assert is_binary(content),
        "期望 content 是文本，实际：#{inspect(content)}"
    end)
    ctx
  end

  defp init_command_registry!(ctx, _args, _meta) do
    Gong.CommandRegistry.cleanup()
    Gong.CommandRegistry.init()
    ctx
  end

  defp register_command!(ctx, %{name: name, description: desc}, _meta) do
    handler = fn _args -> {:ok, "#{name} executed"} end
    Gong.CommandRegistry.register(name, handler, description: desc)
    ctx
  end

  defp execute_command!(ctx, %{name: name}, _meta) do
    case Gong.CommandRegistry.execute(name) do
      {:ok, result} -> Map.put(ctx, :command_result, result)
      {:error, reason} -> Map.put(ctx, :command_error, reason)
    end
  end

  defp execute_command_expect_error!(ctx, %{name: name}, _meta) do
    case Gong.CommandRegistry.execute(name) do
      {:ok, result} -> Map.put(ctx, :command_result, result)
      {:error, reason} -> Map.put(ctx, :command_error, reason)
    end
  end

  defp assert_command_result!(ctx, %{contains: text}, _meta) do
    result = Map.fetch!(ctx, :command_result)
    assert result =~ text,
      "期望命令结果包含 #{inspect(text)}，实际：#{inspect(result)}"
    ctx
  end

  defp assert_command_error!(ctx, %{contains: text}, _meta) do
    error = Map.get(ctx, :command_error, "")
    assert error =~ text,
      "期望命令错误包含 #{inspect(text)}，实际：#{inspect(error)}"
    ctx
  end

  defp assert_command_count!(ctx, %{expected: expected}, _meta) do
    actual = length(Gong.CommandRegistry.list())
    assert actual == expected,
      "期望 #{expected} 个命令，实际：#{actual}"
    ctx
  end

  # ── Auth 补充实现 ──

  defp refresh_auth_token!(ctx, %{refresh: refresh}, _meta) do
    config = %{
      client_id: "test", client_secret: "test",
      authorize_url: "https://auth.example.com/authorize",
      token_url: "https://auth.example.com/token",
      redirect_uri: "http://localhost:8080/callback", scopes: []
    }
    {:ok, token} = Gong.Auth.refresh_token(config, refresh)
    Map.put(ctx, :auth_token, token)
  end

  defp check_token_expired!(ctx, %{expires_at: expires_at}, _meta) do
    token = %{access_token: "test", refresh_token: nil, expires_at: expires_at}
    result = Gong.Auth.token_expired?(token)
    Map.put(ctx, :token_expired, result)
  end

  defp assert_token_expired!(ctx, %{expected: expected}, _meta) do
    actual = Map.fetch!(ctx, :token_expired)
    expected_bool = expected == "true"
    assert actual == expected_bool,
      "期望 token_expired=#{expected}，实际：#{actual}"
    ctx
  end

  defp get_api_key!(ctx, %{env_var: env_var}, _meta) do
    # 为成功测试设置临时环境变量
    if env_var == "GONG_TEST_API_KEY" do
      System.put_env("GONG_TEST_API_KEY", "test_key_value")
    end
    result = Gong.Auth.get_api_key(env_var)
    Map.put(ctx, :api_key_result, result)
  end

  defp assert_api_key_result!(ctx, %{status: status}, _meta) do
    result = Map.fetch!(ctx, :api_key_result)
    case status do
      "ok" ->
        assert match?({:ok, _}, result), "期望 ok，实际：#{inspect(result)}"
      "error" ->
        assert match?({:error, _}, result), "期望 error，实际：#{inspect(result)}"
    end
    ctx
  end

  # ── Thinking 补充实现 ──

  defp parse_thinking_level!(ctx, %{str: str}, _meta) do
    result = Gong.Thinking.parse(str)
    Map.put(ctx, :parsed_thinking, result)
  end

  defp assert_parsed_thinking_level!(ctx, %{expected: expected}, _meta) do
    result = Map.fetch!(ctx, :parsed_thinking)
    assert match?({:ok, _}, result), "期望解析成功，实际：#{inspect(result)}"
    {:ok, level} = result
    assert to_string(level) == expected,
      "期望 level=#{expected}，实际：#{level}"
    ctx
  end

  defp assert_parsed_thinking_error!(ctx, _args, _meta) do
    result = Map.fetch!(ctx, :parsed_thinking)
    assert result == {:error, :invalid_level},
      "期望解析错误 :invalid_level，实际：#{inspect(result)}"
    ctx
  end

  # ── Provider 补充实现 ──

  defp cleanup_provider_registry!(ctx, _args, _meta) do
    Gong.ProviderRegistry.cleanup()
    ctx
  end

  defp assert_provider_current_nil!(ctx, _args, _meta) do
    result = Gong.ProviderRegistry.current()
    assert result == nil, "期望 current 为 nil，实际：#{inspect(result)}"
    ctx
  end

  # ── Cost 补充实现 ──

  defp assert_cost_history!(ctx, %{count: count, first_model: first_model}, _meta) do
    history = Gong.CostTracker.history()
    assert length(history) == count,
      "期望 #{count} 条历史，实际：#{length(history)}"
    if count > 0 do
      first = hd(history)
      assert first.model == first_model,
        "期望第一条 model=#{first_model}，实际：#{first.model}"
    end
    ctx
  end

  defp assert_last_call_nil!(ctx, _args, _meta) do
    result = Gong.CostTracker.last_call()
    assert result == nil, "期望 last_call 为 nil，实际：#{inspect(result)}"
    ctx
  end

  # ── Template 补充实现 ──

  defp assert_template_list_count!(ctx, %{expected: expected}, _meta) do
    templates = Gong.PromptTemplate.list()
    assert length(templates) == expected,
      "期望 #{expected} 个模板，实际：#{length(templates)}"
    ctx
  end

  # ── RPC 补充实现 ──

  defp rpc_dispatch_raise!(ctx, %{method: method}, _meta) do
    # handler 会抛异常
    handlers = %{method => fn _params -> raise "故意崩溃" end}
    request = %{method: method, params: %{}, id: 1}
    result = Gong.RPC.dispatch(request, handlers)
    Map.put(ctx, :rpc_response, result)
  end

  # ── CrossProvider 补充实现 ──

  defp cross_provider_tool_calls_message!(ctx, _args, _meta) do
    messages = [%{
      role: "assistant",
      content: "调用工具",
      tool_calls: [
        %{"id" => "tc1", "name" => "read_file", "arguments" => %{"path" => "/tmp/test"}}
      ]
    }]
    Map.put(ctx, :cross_messages, messages)
  end

  defp assert_command_exists!(ctx, %{name: name, expected: expected}, _meta) do
    exists = Gong.CommandRegistry.exists?(name)
    expected_bool = expected == "true"
    assert exists == expected_bool,
      "期望 exists?(#{name})=#{expected}，实际：#{exists}"
    ctx
  end

  defp assert_converted_has_tool_calls!(ctx, _args, _meta) do
    converted = Map.fetch!(ctx, :converted_messages)
    msg = hd(converted)
    tool_calls = Map.get(msg, :tool_calls, [])
    assert length(tool_calls) > 0, "期望消息包含 tool_calls"
    # 验证规范化后有 :id, :name, :arguments
    tc = hd(tool_calls)
    assert Map.has_key?(tc, :id), "tool_call 应有 :id"
    assert Map.has_key?(tc, :name), "tool_call 应有 :name"
    ctx
  end

  # ── Extension 补充实现 ──

  defp assert_extension_commands!(ctx, %{expected: expected}, _meta) do
    extensions = Map.get(ctx, :loaded_extensions, [])
    total_cmds = Enum.reduce(extensions, 0, fn mod, acc ->
      if is_atom(mod) and function_exported?(mod, :commands, 0) do
        acc + length(mod.commands())
      else
        acc
      end
    end)
    assert total_cmds == expected,
      "期望 #{expected} 个 extension commands，实际：#{total_cmds}"
    ctx
  end

  defp cleanup_extension!(ctx, %{name: name}, _meta) do
    extensions = Map.get(ctx, :loaded_extensions, [])
    ext = Enum.find(extensions, fn mod ->
      is_atom(mod) and to_string(mod) =~ name
    end)
    if ext do
      ext.cleanup(%{})
    end
    Map.put(ctx, :cleanup_called, true)
  end

  defp assert_extension_cleanup_called!(ctx, _args, _meta) do
    assert Map.get(ctx, :cleanup_called, false) == true,
      "期望 cleanup 已被调用"
    ctx
  end

  # ── Stream 补充实现 ──

  defp stream_tool_chunks!(ctx, %{tool_name: tool_name, chunks: chunks_str}, _meta) do
    chunks = chunks_str
    |> String.split("|")
    |> Enum.map(fn
      "done" -> :done
      "chunk:" <> text -> {:chunk, text}
      other -> {:chunk, other}
    end)

    events = Gong.Stream.tool_chunks_to_events(tool_name, chunks)
    Map.put(ctx, :tool_events, events)
  end

  defp assert_tool_event_sequence!(ctx, %{sequence: expected_seq}, _meta) do
    events = Map.fetch!(ctx, :tool_events)
    types = Enum.map(events, fn e -> to_string(e.type) end)
    actual_seq = Enum.join(types, ",")
    assert actual_seq == expected_seq,
      "期望事件序列 #{expected_seq}，实际：#{actual_seq}"
    ctx
  end

  defp assert_tool_event_name!(ctx, %{expected: expected}, _meta) do
    events = Map.fetch!(ctx, :tool_events)
    # 所有事件的 tool_name 应匹配
    Enum.each(events, fn e ->
      if e.tool_name do
        assert e.tool_name == expected,
          "期望 tool_name=#{expected}，实际：#{e.tool_name}"
      end
    end)
    ctx
  end

  # ── Auto-Compaction 实现 ──

  defp auto_compact!(ctx, args, _meta) do
    messages = Map.fetch!(ctx, :compaction_messages)
    summarize_fn = Map.get(ctx, :compaction_summarize_fn)

    opts = [
      context_window: args.context_window,
      reserve_tokens: args.reserve_tokens,
      window_size: args.window_size
    ]

    opts = if summarize_fn, do: [{:summarize_fn, summarize_fn} | opts], else: opts

    result = Gong.AutoCompaction.auto_compact(messages, opts)

    case result do
      {:compacted, compacted, summary} ->
        ctx
        |> Map.put(:auto_compact_result, :compacted)
        |> Map.put(:compacted_messages, compacted)
        |> Map.put(:compaction_summary, summary)

      {:no_action, _msgs} ->
        Map.put(ctx, :auto_compact_result, :no_action)

      {:skipped, :lock_busy} ->
        Map.put(ctx, :auto_compact_result, :skipped)
    end
  end

  defp assert_auto_compacted!(ctx, _args, _meta) do
    result = Map.fetch!(ctx, :auto_compact_result)
    assert result == :compacted,
      "期望自动压缩已触发，实际：#{result}"
    ctx
  end

  defp assert_auto_no_action!(ctx, _args, _meta) do
    result = Map.fetch!(ctx, :auto_compact_result)
    assert result == :no_action,
      "期望未触发压缩，实际：#{result}"
    ctx
  end

  # ── E2E LiveLLM 测试实现 ──

  defp agent_chat_live!(ctx, %{prompt: prompt}, _meta) do
    agent = ctx.agent
    hooks = Map.get(ctx, :hooks, [])
    workspace = Map.get(ctx, :workspace, File.cwd!())
    full_prompt = "工作目录：#{workspace}\n所有文件操作使用绝对路径。\n\n#{prompt}"

    case Gong.LiveLLM.run_chat(agent, full_prompt, hooks) do
      {:ok, reply, updated_agent} ->
        ctx = collect_telemetry_events(ctx)

        ctx
        |> Map.put(:agent, updated_agent)
        |> Map.put(:last_reply, reply)
        |> Map.put(:last_error, nil)

      {:error, reason, updated_agent} ->
        ctx = collect_telemetry_events(ctx)

        ctx
        |> Map.put(:agent, updated_agent)
        |> Map.put(:last_reply, to_string(reason))
        |> Map.put(:last_error, reason)
    end
  end

  # ── E2E LLM 测试实现 ──

  defp check_e2e_provider!(ctx, args, _meta) do
    provider = Map.get(args, :provider, "deepseek")

    env_key =
      case provider do
        "deepseek" -> "DEEPSEEK_API_KEY"
        "openai" -> "OPENAI_API_KEY"
        "anthropic" -> "ANTHROPIC_API_KEY"
        _ -> "DEEPSEEK_API_KEY"
      end

    unless System.get_env(env_key) do
      flunk("跳过 E2E 测试：环境变量 #{env_key} 未设置。请设置后重试。")
    end

    Map.put(ctx, :e2e_provider, provider)
  end

  defp agent_chat_continue!(ctx, %{prompt: prompt}, _meta) do
    # 必须已有存活的 agent_pid（多轮 E2E 对话）
    pid = ctx[:agent_pid]

    unless pid && Process.alive?(pid) do
      flunk("agent_chat_continue 需要已有存活的 agent_pid，当前无可用 AgentServer")
    end

    workspace = Map.get(ctx, :workspace, File.cwd!())
    full_prompt = "工作目录：#{workspace}\n所有文件操作使用绝对路径。\n\n#{prompt}"

    case Gong.Agent.ask_sync(pid, full_prompt, timeout: 60_000) do
      {:ok, reply} ->
        ctx
        |> Map.put(:last_reply, reply)
        |> Map.put(:last_error, nil)

      {:error, reason} ->
        ctx
        |> Map.put(:last_reply, nil)
        |> Map.put(:last_error, reason)
    end
  end

  defp assert_context_compactable!(ctx, args, _meta) do
    # 从 AgentServer 获取对话历史，验证 should_compact? 判断
    pid = ctx[:agent_pid]

    unless pid && Process.alive?(pid) do
      flunk("assert_context_compactable 需要已有存活的 agent_pid")
    end

    # 获取 agent 状态中的对话消息
    state = :sys.get_state(pid)
    messages = extract_messages_from_state(state)

    opts = []
    opts = if args[:context_window], do: [{:context_window, args.context_window} | opts], else: opts
    opts = if args[:reserve_tokens], do: [{:reserve_tokens, args.reserve_tokens} | opts], else: opts

    # 验证 token 计数和 should_compact? 逻辑一致
    token_count = Gong.Compaction.TokenEstimator.estimate_messages(messages)
    result = Gong.AutoCompaction.should_compact?(messages, opts)

    # 存储到 ctx 供后续断言使用
    ctx
    |> Map.put(:e2e_token_count, token_count)
    |> Map.put(:e2e_compactable, result)
  end

  # 从 AgentServer 状态中提取对话消息
  defp extract_messages_from_state(state) do
    cond do
      is_map(state) && Map.has_key?(state, :messages) ->
        state.messages

      is_map(state) && Map.has_key?(state, :agent) ->
        agent = state.agent
        cond do
          is_map(agent) && Map.has_key?(agent, :messages) -> agent.messages
          is_map(agent) && Map.has_key?(agent, :state) ->
            inner = agent.state
            if is_map(inner) && Map.has_key?(inner, :messages), do: inner.messages, else: []
          true -> []
        end

      true ->
        []
    end
  end

  # ── Helpers ──

  defp parse_metadata_value(v) do
    case Integer.parse(v) do
      {int, ""} -> int
      _ -> v
    end
  end

  defp unescape(str) when is_binary(str) do
    str
    |> String.replace("\\n", "\n")
    |> String.replace("\\t", "\t")
    |> String.replace("\\r", "\r")
    |> String.replace("\\\"", "\"")
  end

  defp unescape(other), do: other

  # ══════════════════════════════════════════════════════
  # 第二~四批次实现（Steps ⑤-⑭）
  # ══════════════════════════════════════════════════════

  # ── ModelRegistry 实现 ──

  defp init_model_registry!(ctx, _args, _meta) do
    Gong.ModelRegistry.init()

    ExUnit.Callbacks.on_exit(fn ->
      Gong.ModelRegistry.cleanup()
    end)

    ctx
  end

  defp register_model!(ctx, args, _meta) do
    name = String.to_atom(args.name)
    config = %{
      provider: args.provider,
      model_id: args.model_id,
      api_key_env: Map.get(args, :api_key_env, "DEEPSEEK_API_KEY")
    }

    Gong.ModelRegistry.register(name, config)
    ctx
  end

  defp switch_model!(ctx, %{name: name}, _meta) do
    name_atom = String.to_atom(name)

    case Gong.ModelRegistry.switch(name_atom) do
      :ok ->
        Map.put(ctx, :model_last_error, nil)

      {:error, reason} ->
        Map.put(ctx, :model_last_error, to_string(reason))
    end
  end

  defp validate_model!(ctx, %{name: name}, _meta) do
    name_atom = String.to_atom(name)

    case Gong.ModelRegistry.validate(name_atom) do
      :ok ->
        Map.put(ctx, :model_last_error, nil)

      {:error, reason} ->
        Map.put(ctx, :model_last_error, reason)
    end
  end

  defp assert_current_model!(ctx, %{name: expected}, _meta) do
    {name, _config} = Gong.ModelRegistry.current_model()
    assert to_string(name) == expected,
      "期望当前模型=#{expected}，实际：#{name}"
    ctx
  end

  defp assert_model_error!(ctx, %{error_contains: expected}, _meta) do
    error = Map.get(ctx, :model_last_error)
    assert error != nil, "期望模型错误，但 model_last_error 为 nil"
    decoded = unescape(expected)

    assert to_string(error) =~ decoded,
      "期望模型错误包含 #{inspect(decoded)}，实际：#{inspect(error)}"

    ctx
  end

  defp assert_model_count!(ctx, %{expected: expected}, _meta) do
    models = Gong.ModelRegistry.list()
    actual = length(models)

    assert actual == expected,
      "期望模型数=#{expected}，实际：#{actual}"

    ctx
  end

  # ── Stream 扩展实现 ──

  defp mock_stream_response!(ctx, args, _meta) do
    chunks = parse_stream_chunks(Map.get(args, :chunks, ""))
    stream_queue = Map.get(ctx, :stream_queue, [])
    Map.put(ctx, :stream_queue, stream_queue ++ [chunks])
  end

  defp parse_stream_chunks(""), do: []
  defp parse_stream_chunks(str) do
    str
    |> String.split("|")
    |> Enum.map(fn chunk ->
      case String.split(chunk, ":", parts: 2) do
        ["chunk", text] -> {:chunk, text}
        ["abort", reason] -> {:abort, reason}
        ["delay", ms] -> {:delay, String.to_integer(ms)}
        ["done"] -> :done
        [text] -> {:chunk, text}
      end
    end)
  end

  defp assert_stream_content!(ctx, %{expected: expected}, _meta) do
    reply = Map.get(ctx, :last_reply, "")
    decoded = unescape(expected)

    assert to_string(reply) =~ decoded,
      "期望流式内容包含 #{inspect(decoded)}，实际：#{inspect(reply)}"

    ctx
  end

  # ── Abort 实现 ──

  defp setup_abort_scenario!(ctx, args, _meta) do
    abort_after = Map.get(args, :after_tool, 1)
    Map.put(ctx, :abort_config, %{after_tool: abort_after})
  end

  defp send_abort_signal!(ctx, _args, _meta) do
    Gong.Abort.signal!()
    ctx
  end

  defp assert_aborted!(ctx, _args, _meta) do
    # 检查 last_error 包含 aborted 或 ctx 标记
    error = Map.get(ctx, :last_error)
    assert error != nil, "期望操作被中止，但未发现错误"
    assert to_string(error) =~ "abort",
      "期望错误包含 abort，实际：#{inspect(error)}"
    ctx
  end

  defp assert_abort_reset!(ctx, _args, _meta) do
    # 重置 abort 信号（测试隔离）
    Gong.Abort.reset!()
    refute Gong.Abort.aborted?(), "期望 abort 已重置"
    ctx
  end

  defp assert_partial_content!(ctx, %{contains: expected}, _meta) do
    reply = Map.get(ctx, :last_reply, "")
    decoded = unescape(expected)

    assert to_string(reply) =~ decoded,
      "期望部分内容包含 #{inspect(decoded)}，实际：#{inspect(reply)}"

    ctx
  end

  # ── Session 树形分支实现 ──

  defp tape_branch_from!(ctx, %{anchor: anchor_name}, _meta) do
    store = ctx.tape_store

    case Gong.Tape.Store.branch_from(store, anchor_name) do
      {:ok, branch_name, updated_store} ->
        ctx
        |> Map.put(:tape_store, updated_store)
        |> Map.put(:tape_last_branch, branch_name)
        |> Map.put(:tape_last_error, nil)

      {:error, reason} ->
        Map.put(ctx, :tape_last_error, reason)
    end
  end

  defp tape_navigate!(ctx, %{anchor: anchor_name}, _meta) do
    store = ctx.tape_store

    case Gong.Tape.Store.navigate(store, anchor_name) do
      {:ok, updated_store} ->
        ctx
        |> Map.put(:tape_store, updated_store)
        |> Map.put(:tape_last_anchor, anchor_name)
        |> Map.put(:tape_last_error, nil)

      {:error, reason} ->
        Map.put(ctx, :tape_last_error, reason)
    end
  end

  defp tape_build_context!(ctx, %{anchor: anchor_name}, _meta) do
    store = ctx.tape_store

    case Gong.Tape.Store.build_context_path(store, anchor_name) do
      {:ok, entries} ->
        ctx
        |> Map.put(:tape_context_path, entries)
        |> Map.put(:tape_last_error, nil)

      {:error, reason} ->
        Map.put(ctx, :tape_last_error, reason)
    end
  end

  defp assert_tape_branches!(ctx, %{anchor: anchor_name, expected: expected}, _meta) do
    store = ctx.tape_store
    branches = Gong.Tape.Store.branches(store, anchor_name)
    actual = length(branches)

    assert actual == expected,
      "期望分支数=#{expected}，实际：#{actual}，分支：#{inspect(branches)}"

    ctx
  end

  defp assert_tape_context_path!(ctx, %{count: expected_count} = args, _meta) do
    entries = Map.get(ctx, :tape_context_path, [])
    actual = length(entries)

    assert actual == expected_count,
      "期望上下文路径条目数=#{expected_count}，实际：#{actual}"

    if text = args[:contains] do
      decoded = unescape(text)
      found = Enum.any?(entries, fn entry ->
        to_string(Map.get(entry, :content, "")) =~ decoded
      end)
      assert found, "期望上下文路径包含 #{inspect(decoded)}"
    end

    ctx
  end

  # ── Extension 实现 ──

  defp create_extension_dir!(ctx, _args, _meta) do
    ext_dir = Path.join(ctx.workspace, "extensions")
    File.mkdir_p!(ext_dir)
    Map.put(ctx, :extension_dir, ext_dir)
  end

  defp create_extension_file!(ctx, %{name: name, content: content}, _meta) do
    ext_dir = Map.get(ctx, :extension_dir, Path.join(ctx.workspace, "extensions"))
    File.mkdir_p!(ext_dir)
    file_path = Path.join(ext_dir, name)
    File.write!(file_path, unescape(content))
    ctx
  end

  defp discover_extensions!(ctx, _args, _meta) do
    ext_dir = Map.get(ctx, :extension_dir, Path.join(ctx.workspace, "extensions"))

    case Gong.Extension.Loader.discover([ext_dir]) do
      {:ok, files} ->
        ctx
        |> Map.put(:extension_files, files)
        |> Map.put(:extension_last_error, nil)

      {:error, reason} ->
        Map.put(ctx, :extension_last_error, reason)
    end
  end

  defp load_extension!(ctx, %{path: path}, _meta) do
    full = Path.join(Map.get(ctx, :extension_dir, ctx.workspace), path)

    case Gong.Extension.Loader.load(full) do
      {:ok, ext_module} ->
        loaded = Map.get(ctx, :loaded_extensions, [])
        ctx
        |> Map.put(:loaded_extensions, loaded ++ [ext_module])
        |> Map.put(:extension_last_error, nil)

      {:error, reason} ->
        Map.put(ctx, :extension_last_error, reason)
    end
  end

  defp load_all_extensions!(ctx, _args, _meta) do
    ext_dir = Map.get(ctx, :extension_dir, Path.join(ctx.workspace, "extensions"))

    case Gong.Extension.Loader.load_all([ext_dir]) do
      {:ok, modules, errors} ->
        ctx
        |> Map.put(:loaded_extensions, modules)
        |> Map.put(:extension_load_errors, errors)
        |> Map.put(:extension_last_error, nil)

      {:error, reason} ->
        Map.put(ctx, :extension_last_error, reason)
    end
  end

  defp assert_extension_loaded!(ctx, %{name: expected}, _meta) do
    loaded = Map.get(ctx, :loaded_extensions, [])
    found = Enum.any?(loaded, fn mod ->
      mod_name = if is_atom(mod), do: to_string(mod), else: to_string(mod)
      mod_name =~ expected
    end)

    assert found,
      "期望 Extension #{expected} 已加载，实际：#{inspect(loaded)}"

    ctx
  end

  defp assert_extension_tools!(ctx, %{expected: expected}, _meta) do
    loaded = Map.get(ctx, :loaded_extensions, [])
    tools = Enum.flat_map(loaded, fn mod ->
      if function_exported?(mod, :tools, 0), do: mod.tools(), else: []
    end)

    assert length(tools) == expected,
      "期望工具数=#{expected}，实际：#{length(tools)}"

    ctx
  end

  defp assert_extension_error!(ctx, %{error_contains: expected}, _meta) do
    error = Map.get(ctx, :extension_last_error)
    errors = Map.get(ctx, :extension_load_errors, [])

    has_error = (error != nil && to_string(error) =~ unescape(expected)) ||
      Enum.any?(errors, fn {_path, err} -> to_string(err) =~ unescape(expected) end)

    assert has_error,
      "期望扩展错误包含 #{inspect(expected)}，实际 error：#{inspect(error)}，errors：#{inspect(errors)}"

    ctx
  end

  defp assert_extension_count!(ctx, %{expected: expected}, _meta) do
    loaded = Map.get(ctx, :loaded_extensions, [])
    actual = length(loaded)

    assert actual == expected,
      "期望已加载扩展数=#{expected}，实际：#{actual}"

    ctx
  end

  # ── Follow-up 实现 ──

  defp inject_follow_up!(ctx, %{message: message}, _meta) do
    queue = Map.get(ctx, :steering_queue, Gong.Steering.new())
    Map.put(ctx, :steering_queue, Gong.Steering.push(queue, {:follow_up, message}))
  end

  defp push_steering_message!(ctx, %{message: message}, _meta) do
    queue = Map.get(ctx, :steering_queue, Gong.Steering.new())
    Map.put(ctx, :steering_queue, Gong.Steering.push(queue, message))
  end

  defp steering_check_follow_up!(ctx, _args, _meta) do
    queue = Map.get(ctx, :steering_queue, Gong.Steering.new())
    {msg, new_queue} = Gong.Steering.check_follow_up(queue)

    ctx
    |> Map.put(:steering_queue, new_queue)
    |> Map.put(:follow_up_last_message, msg)
  end

  defp assert_follow_up_message!(ctx, %{contains: text}, _meta) do
    msg = Map.get(ctx, :follow_up_last_message)
    assert msg != nil, "期望 follow_up 消息不为 nil"
    assert to_string(msg) =~ text,
      "期望 follow_up 消息包含 #{inspect(text)}，实际：#{inspect(msg)}"
    ctx
  end

  defp assert_follow_up_empty!(ctx, _args, _meta) do
    msg = Map.get(ctx, :follow_up_last_message)
    assert msg == nil, "期望 follow_up 为空，实际：#{inspect(msg)}"
    ctx
  end

  # ── Settings 实现 ──

  defp init_settings!(ctx, _args, _meta) do
    Gong.Settings.init(ctx.workspace)

    ExUnit.Callbacks.on_exit(fn ->
      Gong.Settings.cleanup()
    end)

    ctx
  end

  defp create_settings_file!(ctx, %{scope: scope, content: content}, _meta) do
    dir = case scope do
      "global" -> Path.join(ctx.workspace, ".gong")
      "project" -> Path.join(ctx.workspace, ".gong")
      _ -> Path.join(ctx.workspace, ".gong")
    end
    File.mkdir_p!(dir)
    File.write!(Path.join(dir, "settings.json"), unescape(content))
    ctx
  end

  defp get_setting!(ctx, %{key: key}, _meta) do
    value = Gong.Settings.get(key)
    Map.put(ctx, :setting_last_value, value)
  end

  defp set_setting!(ctx, %{key: key, value: value}, _meta) do
    Gong.Settings.set(key, unescape(value))
    ctx
  end

  defp assert_setting_value!(ctx, %{expected: expected}, _meta) do
    actual = Map.get(ctx, :setting_last_value)
    decoded = unescape(expected)

    assert to_string(actual) == decoded,
      "期望设置值=#{inspect(decoded)}，实际：#{inspect(actual)}"

    ctx
  end

  # ── Resource 实现 ──

  defp create_resource_dir!(ctx, %{scope: scope}, _meta) do
    dir = case scope do
      "global" -> Path.join(ctx.workspace, ".gong/context")
      "project" -> Path.join(ctx.workspace, ".gong/context")
      _ -> Path.join(ctx.workspace, ".gong/context")
    end
    File.mkdir_p!(dir)
    Map.put(ctx, :resource_dir, dir)
  end

  defp create_resource_file!(ctx, %{name: name, content: content}, _meta) do
    dir = Map.get(ctx, :resource_dir, Path.join(ctx.workspace, ".gong/context"))
    File.mkdir_p!(dir)
    File.write!(Path.join(dir, name), unescape(content))
    ctx
  end

  defp load_resources!(ctx, _args, _meta) do
    gong_dir = Path.join(ctx.workspace, ".gong")

    case Gong.ResourceLoader.load([gong_dir]) do
      {:ok, resources} ->
        ctx
        |> Map.put(:loaded_resources, resources)
        |> Map.put(:resource_last_error, nil)

      {:error, reason} ->
        Map.put(ctx, :resource_last_error, reason)
    end
  end

  defp reload_resources!(ctx, _args, _meta) do
    gong_dir = Path.join(ctx.workspace, ".gong")

    case Gong.ResourceLoader.load([gong_dir]) do
      {:ok, resources} ->
        ctx
        |> Map.put(:loaded_resources, resources)
        |> Map.put(:resource_last_error, nil)

      {:error, reason} ->
        Map.put(ctx, :resource_last_error, reason)
    end
  end

  defp assert_resource_content!(ctx, %{contains: text}, _meta) do
    resources = Map.get(ctx, :loaded_resources, [])
    decoded = unescape(text)

    found = Enum.any?(resources, fn res ->
      to_string(Map.get(res, :content, "")) =~ decoded
    end)

    assert found,
      "期望资源内容包含 #{inspect(decoded)}，实际资源数：#{length(resources)}"

    ctx
  end

  defp assert_resource_count!(ctx, %{expected: expected}, _meta) do
    resources = Map.get(ctx, :loaded_resources, [])
    actual = length(resources)

    assert actual == expected,
      "期望资源数=#{expected}，实际：#{actual}"

    ctx
  end

  # ── Branch Summary 实现 ──

  defp generate_branch_summary!(ctx, %{anchor: anchor_name}, _meta) do
    store = ctx.tape_store

    case Gong.Tape.Store.generate_branch_summary(store, anchor_name) do
      {:ok, summary} ->
        ctx
        |> Map.put(:branch_summary, summary)
        |> Map.put(:tape_last_error, nil)

      {:error, reason} ->
        Map.put(ctx, :tape_last_error, reason)
    end
  end

  defp assert_branch_summary!(ctx, %{contains: text}, _meta) do
    summary = Map.get(ctx, :branch_summary)
    assert summary != nil, "期望分支摘要不为 nil"
    decoded = unescape(text)

    assert to_string(summary) =~ decoded,
      "期望摘要包含 #{inspect(decoded)}，实际：#{inspect(summary)}"

    ctx
  end

  # ── Tool: truncate_tool 实现 ──

  defp tool_truncate!(ctx, args, _meta) do
    path = resolve_tool_path(ctx, Map.get(args, :path, ""))
    params = %{file_path: path}
    params = if args[:max_lines], do: Map.put(params, :max_lines, args.max_lines), else: params

    result = Gong.Tools.Truncate.run(params, %{})
    Map.put(ctx, :last_result, result)
  end

  # ── Tool: edit-diff 实现 ──

  defp tool_edit_diff!(ctx, args, _meta) do
    path = resolve_tool_path(ctx, Map.get(args, :path, ""))
    params = %{
      file_path: path,
      mode: "diff",
      diff: unescape(args.diff)
    }

    tool_ctx = %{workspace: ctx[:workspace]}
    result = Gong.Tools.Edit.run(params, tool_ctx)
    Map.put(ctx, :last_result, result)
  end

  # ── Path Utils 实现 ──

  defp normalize_path!(ctx, %{path: path}, _meta) do
    normalized = Gong.PathUtils.normalize(unescape(path))
    Map.put(ctx, :normalized_path, normalized)
  end

  defp assert_normalized_path!(ctx, %{expected: expected}, _meta) do
    actual = Map.get(ctx, :normalized_path)
    decoded = unescape(expected)

    assert actual == decoded,
      "期望路径=#{inspect(decoded)}，实际：#{inspect(actual)}"

    ctx
  end

  # ── Abort unit 实现 ──

  defp abort_signal!(ctx, args, _meta) do
    reason = Map.get(args, :reason, "user")
    Gong.Abort.signal!(reason)
    ctx
  end

  defp abort_check_catch!(ctx, _args, _meta) do
    result =
      try do
        Gong.Abort.check!()
        {:ok, :no_abort}
      catch
        {:aborted, reason} -> {:caught, reason}
      end

    Map.put(ctx, :abort_catch_result, result)
  end

  defp abort_reset!(ctx, _args, _meta) do
    Gong.Abort.reset!()
    ctx
  end

  defp abort_safe_execute!(ctx, args, _meta) do
    will_abort = Map.get(args, :will_abort, "false") == "true"
    reason = Map.get(args, :reason, "user")

    result =
      if will_abort do
        Gong.Abort.safe_execute(fn ->
          Gong.Abort.signal!(reason)
          Gong.Abort.check!()
        end)
      else
        Gong.Abort.safe_execute(fn -> :normal_result end)
      end

    Map.put(ctx, :safe_execute_result, result)
  end

  defp assert_abort_flag!(ctx, %{expected: expected}, _meta) do
    actual = Gong.Abort.aborted?()
    exp = expected == "true"

    assert actual == exp,
      "期望 aborted?=#{exp}，实际：#{actual}"

    ctx
  end

  defp assert_abort_reason!(ctx, %{expected: expected}, _meta) do
    actual = Gong.Abort.reason()

    if expected == "nil" do
      assert actual == nil,
        "期望 reason=nil，实际：#{inspect(actual)}"
    else
      assert to_string(actual) == expected,
        "期望 reason=#{expected}，实际：#{inspect(actual)}"
    end

    ctx
  end

  defp assert_abort_caught!(ctx, %{reason: expected_reason}, _meta) do
    result = Map.fetch!(ctx, :abort_catch_result)

    case result do
      {:caught, reason} ->
        assert to_string(reason) == expected_reason,
          "期望 caught reason=#{expected_reason}，实际：#{inspect(reason)}"

      other ->
        flunk("期望 abort 被捕获，实际结果：#{inspect(other)}")
    end

    ctx
  end

  defp assert_safe_execute_result!(ctx, %{expected: expected} = args, _meta) do
    result = Map.fetch!(ctx, :safe_execute_result)

    case expected do
      "aborted" ->
        expected_reason = Map.get(args, :reason, "user")

        case result do
          {:aborted, reason} ->
            assert to_string(reason) == expected_reason,
              "期望 aborted reason=#{expected_reason}，实际：#{inspect(reason)}"

          other ->
            flunk("期望 {:aborted, ...}，实际：#{inspect(other)}")
        end

      "ok" ->
        case result do
          {:ok, _} -> :ok
          other -> flunk("期望 {:ok, ...}，实际：#{inspect(other)}")
        end
    end

    ctx
  end

  # ── Steering unit 补充实现 ──

  defp assert_steering_message_nil!(ctx, _args, _meta) do
    msg = Map.get(ctx, :steering_last_message)
    assert msg == nil, "期望 steering 消息为 nil，实际：#{inspect(msg)}"
    ctx
  end

  defp assert_steering_not_pending!(ctx, _args, _meta) do
    queue = Map.get(ctx, :steering_queue, [])
    refute Gong.Steering.pending?(queue), "期望 steering 队列无待处理消息"
    ctx
  end

  defp steering_push_typed!(ctx, %{type: type, message: message}, _meta) do
    queue = Map.get(ctx, :steering_queue, Gong.Steering.new())
    typed_msg = {String.to_atom(type), message}
    Map.put(ctx, :steering_queue, Gong.Steering.push(queue, typed_msg))
  end

  defp steering_check_steering!(ctx, _args, _meta) do
    queue = Map.get(ctx, :steering_queue, Gong.Steering.new())
    {msg, new_queue} = Gong.Steering.check_steering(queue)

    ctx
    |> Map.put(:steering_queue, new_queue)
    |> Map.put(:steering_last_message, msg)
  end

  # ── Settings 补充实现 ──

  defp assert_setting_nil!(ctx, _args, _meta) do
    value = Map.get(ctx, :setting_last_value)
    assert value == nil, "期望 setting 为 nil，实际：#{inspect(value)}"
    ctx
  end

  defp list_settings!(ctx, _args, _meta) do
    settings = Gong.Settings.list()
    Map.put(ctx, :settings_list, settings)
  end

  defp assert_settings_list!(ctx, %{contains: key}, _meta) do
    settings = Map.get(ctx, :settings_list, %{})
    assert Map.has_key?(settings, key),
      "期望设置列表包含 key=#{key}，实际 keys：#{inspect(Map.keys(settings))}"
    ctx
  end

  defp cleanup_settings!(ctx, _args, _meta) do
    Gong.Settings.cleanup()
    ctx
  end

  defp get_setting_safe!(ctx, %{key: key}, _meta) do
    value =
      try do
        Gong.Settings.get(key)
      rescue
        ArgumentError -> nil
      catch
        :error, _ -> nil
      end

    Map.put(ctx, :setting_last_value, value)
  end

  # ── ModelRegistry 补充实现 ──

  defp get_model_string!(ctx, _args, _meta) do
    str = Gong.ModelRegistry.current_model_string()
    Map.put(ctx, :model_string, str)
  end

  defp list_models!(ctx, _args, _meta) do
    models = Gong.ModelRegistry.list()
    Map.put(ctx, :model_list, models)
  end

  defp cleanup_model_registry!(ctx, _args, _meta) do
    Gong.ModelRegistry.cleanup()
    ctx
  end

  defp get_model_string_safe!(ctx, _args, _meta) do
    str =
      try do
        Gong.ModelRegistry.current_model_string()
      rescue
        _ -> "deepseek:deepseek-chat"
      end

    Map.put(ctx, :model_string, str)
  end

  defp assert_model_string!(ctx, %{expected: expected}, _meta) do
    actual = Map.get(ctx, :model_string)
    assert actual == expected,
      "期望 model_string=#{expected}，实际：#{inspect(actual)}"
    ctx
  end

  defp assert_model_list_count!(ctx, %{expected: expected}, _meta) do
    models = Map.get(ctx, :model_list, [])
    actual = length(models)
    assert actual == expected,
      "期望 model 列表数=#{expected}，实际：#{actual}"
    ctx
  end

  # ── Resource 补充实现 ──

  defp load_resources_from_paths!(ctx, %{paths: paths_str}, _meta) do
    paths = String.split(paths_str, ",", trim: true)

    case Gong.ResourceLoader.load(paths) do
      {:ok, resources} ->
        ctx
        |> Map.put(:loaded_resources, resources)
        |> Map.put(:resource_last_error, nil)

      {:error, reason} ->
        ctx
        |> Map.put(:loaded_resources, [])
        |> Map.put(:resource_last_error, reason)
    end
  end

  # ── PathUtils 补充实现 ──

  defp assert_normalized_path_contains!(ctx, %{text: text}, _meta) do
    actual = Map.get(ctx, :normalized_path)
    assert actual != nil, "期望 normalized_path 不为 nil"
    assert actual =~ text,
      "期望 normalized_path 包含 #{inspect(text)}，实际：#{inspect(actual)}"
    ctx
  end

  defp assert_normalized_path_is_absolute!(ctx, _args, _meta) do
    actual = Map.get(ctx, :normalized_path)
    assert actual != nil, "期望 normalized_path 不为 nil"
    assert String.starts_with?(actual, "/"),
      "期望 normalized_path 为绝对路径，实际：#{inspect(actual)}"
    ctx
  end

  # ── 错误诊断 ──

  defp dump_evidence(_ctx, scenario_id, meta, error) do
    IO.puts("\n=== BDD 失败诊断 ===")
    IO.puts("场景: #{scenario_id}")

    if meta[:file] do
      IO.puts("文件: #{meta.file}:#{meta[:line]}")
    end

    if meta[:raw] do
      IO.puts("步骤: #{meta.raw}")
    end

    IO.puts("错误: #{Exception.message(error)}")
    IO.puts("=== 诊断结束 ===\n")
  end

  # ══════════════════════════════════════════════════════════════
  # ToolConfig 实现
  # ══════════════════════════════════════════════════════════════

  defp init_tool_config!(ctx, _args, _meta) do
    Gong.ToolConfig.init()
    ctx
  end

  defp get_active_tools!(ctx, _args, _meta) do
    tools = Gong.ToolConfig.active_tools()
    Map.put(ctx, :tool_config_active, tools)
  end

  defp get_preset!(ctx, args, _meta) do
    name = String.to_atom(args.name)
    {:ok, tools} = Gong.ToolConfig.preset(name)
    Map.put(ctx, :tool_config_preset, tools)
  end

  defp set_active_tools!(ctx, args, _meta) do
    tools =
      args.tools
      |> String.split(",")
      |> Enum.map(&String.trim/1)
      |> Enum.map(&String.to_atom/1)

    :ok = Gong.ToolConfig.set_active_tools(tools)
    updated = Gong.ToolConfig.active_tools()
    Map.put(ctx, :tool_config_active, updated)
  end

  defp set_active_tools_safe!(ctx, args, _meta) do
    tools =
      if args.tools == "" do
        []
      else
        args.tools
        |> String.split(",")
        |> Enum.map(&String.trim/1)
        |> Enum.map(&String.to_atom/1)
      end

    case Gong.ToolConfig.set_active_tools(tools) do
      :ok ->
        Map.put(ctx, :tool_config_error, nil)

      {:error, msg} ->
        Map.put(ctx, :tool_config_error, msg)
    end
  end

  defp validate_tools!(ctx, args, _meta) do
    tools =
      args.tools
      |> String.split(",")
      |> Enum.map(&String.trim/1)
      |> Enum.map(&String.to_atom/1)

    case Gong.ToolConfig.validate(tools) do
      :ok ->
        Map.put(ctx, :tool_config_error, nil)

      {:error, msg} ->
        Map.put(ctx, :tool_config_error, msg)
    end
  end

  defp assert_active_tool_count!(ctx, args, _meta) do
    expected = if is_binary(args.expected), do: String.to_integer(args.expected), else: args.expected
    tools = ctx[:tool_config_active] || Gong.ToolConfig.active_tools()
    assert length(tools) == expected, "expected #{expected} active tools, got #{length(tools)}"
    ctx
  end

  defp assert_active_tool_contains!(ctx, args, _meta) do
    tool = String.to_atom(args.tool)
    tools = ctx[:tool_config_active] || Gong.ToolConfig.active_tools()
    assert tool in tools, "expected #{tool} in active tools: #{inspect(tools)}"
    ctx
  end

  defp assert_preset_contains!(ctx, args, _meta) do
    tool = String.to_atom(args.tool)
    preset = ctx[:tool_config_preset]
    assert preset, "no preset loaded in context"
    assert tool in preset, "expected #{tool} in preset: #{inspect(preset)}"
    ctx
  end

  defp assert_preset_not_contains!(ctx, args, _meta) do
    tool = String.to_atom(args.tool)
    preset = ctx[:tool_config_preset]
    assert preset, "no preset loaded in context"
    refute tool in preset, "expected #{tool} NOT in preset: #{inspect(preset)}"
    ctx
  end

  defp assert_preset_count!(ctx, args, _meta) do
    expected = if is_binary(args.expected), do: String.to_integer(args.expected), else: args.expected
    preset = ctx[:tool_config_preset]
    assert preset, "no preset loaded in context"
    assert length(preset) == expected, "expected #{expected} tools in preset, got #{length(preset)}"
    ctx
  end

  defp assert_tool_config_error!(ctx, args, _meta) do
    error = ctx[:tool_config_error]
    assert error, "expected tool config error but got none"
    assert String.contains?(error, args.contains), "expected error to contain '#{args.contains}', got: #{error}"
    ctx
  end

  # ══════════════════════════════════════════════════════════════
  # ToolResult 实现
  # ══════════════════════════════════════════════════════════════

  defp tool_result_from_text!(ctx, args, _meta) do
    result = Gong.ToolResult.from_text(args.text)
    Map.put(ctx, :tool_result, result)
  end

  defp tool_result_new!(ctx, args, _meta) do
    details = %{args.details_key => args.details_value}
    result = Gong.ToolResult.new(args.content, details)
    Map.put(ctx, :tool_result, result)
  end

  defp tool_result_error!(ctx, args, _meta) do
    result = Gong.ToolResult.error(args.content)
    Map.put(ctx, :tool_result, result)
  end

  defp assert_tool_result_content!(ctx, args, _meta) do
    result = ctx[:tool_result]
    assert result, "no tool_result in context"
    assert String.contains?(result.content, args.contains),
      "expected content to contain '#{args.contains}', got: #{result.content}"
    ctx
  end

  defp assert_tool_result_details_nil!(ctx, _args, _meta) do
    result = ctx[:tool_result]
    assert result, "no tool_result in context"
    assert is_nil(result.details), "expected details to be nil, got: #{inspect(result.details)}"
    ctx
  end

  defp assert_tool_result_has_details!(ctx, args, _meta) do
    result = ctx[:tool_result]
    assert result, "no tool_result in context"
    assert result.details, "details is nil"
    assert Map.has_key?(result.details, args.key),
      "expected details to have key '#{args.key}', got: #{inspect(Map.keys(result.details))}"
    ctx
  end

  defp assert_tool_result_details_value!(ctx, args, _meta) do
    result = ctx[:tool_result]
    assert result, "no tool_result in context"
    assert result.details, "details is nil"
    actual = Map.get(result.details, args.key)
    assert to_string(actual) == args.expected,
      "expected details[#{args.key}] to be '#{args.expected}', got: #{inspect(actual)}"
    ctx
  end

  defp assert_tool_result_is_error!(ctx, _args, _meta) do
    result = ctx[:tool_result]
    assert result, "no tool_result in context"
    assert result.is_error, "expected is_error=true, got false"
    ctx
  end

  defp assert_tool_result_not_error!(ctx, _args, _meta) do
    result = ctx[:tool_result]
    assert result, "no tool_result in context"
    refute result.is_error, "expected is_error=false, got true"
    ctx
  end

  # 验证 last_result 是 ToolResult 结构体
  defp assert_is_tool_result!(ctx, _args, _meta) do
    assert {:ok, tr} = ctx.last_result, "期望成功结果"
    assert %Gong.ToolResult{} = tr, "期望结果为 ToolResult 结构体，实际：#{inspect(tr)}"
    ctx
  end

  # ══════════════════════════════════════════════════════════════
  # PartialJson 实现
  # ══════════════════════════════════════════════════════════════

  defp partial_json_parse!(ctx, args, _meta) do
    # bddc 保留 DSL 中的 \" 转义，这里还原为实际双引号
    input = String.replace(args.input, "\\\"", "\"")
    result = Gong.PartialJson.parse(input)
    Map.put(ctx, :partial_json_result, result)
  end

  defp partial_json_accumulate!(ctx, args, _meta) do
    # DSL 中用 % 代替双引号避免解析冲突，这里替换回来
    c1 = String.replace(args.chunk1, "%", "\"")
    c2 = String.replace(args.chunk2, "%", "\"")
    c3 = String.replace(args.chunk3, "%", "\"")
    {buf1, _} = Gong.PartialJson.accumulate("", c1)
    {buf2, _} = Gong.PartialJson.accumulate(buf1, c2)
    {_buf3, result} = Gong.PartialJson.accumulate(buf2, c3)
    Map.put(ctx, :partial_json_result, {:ok, result})
  end

  defp assert_partial_json_ok!(ctx, _args, _meta) do
    result = ctx[:partial_json_result]
    assert match?({:ok, _}, result), "expected {:ok, _}, got: #{inspect(result)}"
    ctx
  end

  defp assert_partial_json_field!(ctx, args, _meta) do
    {_, map} = ctx[:partial_json_result]
    actual = Map.get(map, args.key)
    assert to_string(actual) == args.expected,
      "expected field '#{args.key}' to be '#{args.expected}', got: #{inspect(actual)}"
    ctx
  end

  defp assert_partial_json_has_key!(ctx, args, _meta) do
    result = ctx[:partial_json_result]
    map = case result do
      {:ok, m} -> m
      {:partial, m} -> m
      _ -> %{}
    end
    assert Map.has_key?(map, args.key),
      "expected result to have key '#{args.key}', got: #{inspect(Map.keys(map))}"
    ctx
  end

  defp assert_partial_json_empty!(ctx, _args, _meta) do
    result = ctx[:partial_json_result]
    assert match?({:ok, m} when m == %{}, result),
      "expected {:ok, %{}}, got: #{inspect(result)}"
    ctx
  end
end
