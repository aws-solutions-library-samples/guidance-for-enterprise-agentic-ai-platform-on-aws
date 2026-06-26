<!-- Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved. -->
<!-- SPDX-License-Identifier: MIT-0 -->

# Streaming Guide for Agents

## Overview

Your agent sends streaming events in SSE format. This guide explains the streaming event structure and how to consume it from any client.

## How Streaming Works

1. **Your agent sends streaming events** (SSE format)
2. **Clients** read the SSE stream and parse events based on the agent pattern
3. **Parsers emit typed events** (text, tool_use_start, tool_use_delta, tool_result, message, result, lifecycle)

---

## Current Implementation

### Backend: Strands Agent

**File:** `patterns/strands-single-agent/basic_agent.py`

The backend yields all raw Strands streaming events, serialized to JSON-safe dicts:

```python
async for event in agent.stream_async(user_query):
    yield json.loads(json.dumps(dict(event), default=str))
```

**Note:** Strands events can contain non-JSON-serializable Python objects (agent instances, UUIDs, `ModelStopReason` tuples, etc.). The `json.dumps(default=str)` call converts these to strings, ensuring all events are safe to send over SSE.

### Event Structure

Strands provides these event types:

- `data`: Text chunks (accumulate as they arrive)
- `current_tool_use`: Tool name, ID, and input parameters (with `delta` for streaming)
- `message`: Final structured message with full content (assistant with `toolUse`, user with `toolResult`)
- `result`: AgentResult with stop reason and metrics
- `init_event_loop`, `start_event_loop`, `complete`: Lifecycle markers
- `tool_stream_event`: Events streamed from tool execution
- `event`: Raw Bedrock Converse events (used by the alternative converse parser below)

```javascript
// Text streaming
data: {"data": "Hello"}
data: {"data": " there"}

// Tool use start — first delta has empty input
data: {"current_tool_use": {"toolUseId": "tool_abc123", "name": "text_analysis"}, "delta": {"toolUse": {"input": ""}}}

// Tool input streaming
data: {"current_tool_use": {"toolUseId": "tool_abc123", "name": "text_analysis"}, "delta": {"toolUse": {"input": "{\"text\": \"hello\"}"}}}

// Complete assistant message
data: {"message": {"role": "assistant", "content": [{"toolUse": {"toolUseId": "tool_abc123", "name": "text_analysis", "input": {"text": "hello"}}}]}}

// Tool result (user message with toolResult blocks)
data: {"message": {"role": "user", "content": [{"toolResult": {"toolUseId": "tool_abc123", "content": [{"text": "Analysis complete: 1 word"}]}}]}}

// Final result
data: {"result": {"stop_reason": "end_turn"}}

// Lifecycle events
data: {"init_event_loop": true}
data: {"start_event_loop": true}
```

**Reference:** [Strands Streaming Documentation](https://strandsagents.com/latest/documentation/docs/user-guide/concepts/streaming/overview/)

---

## Alternative: Using Raw Converse Events

Instead of parsing Strands schema events, you can also parse the raw Bedrock Converse events nested under the `event` key. This gives you lower-level access to the Converse stream API structures.

### Event Structure

Converse events are nested under the `event` key:

```javascript
// Message lifecycle
data: {"event": {"messageStart": {"role": "assistant"}}}

// Text streaming
data: {"event": {"contentBlockDelta": {"contentBlockIndex": 0, "delta": {"text": "Hello"}}}}
data: {"event": {"contentBlockDelta": {"contentBlockIndex": 0, "delta": {"text": " there"}}}}

// Tool use start
data: {"event": {"contentBlockStart": {"contentBlockIndex": 1, "start": {"toolUse": {"toolUseId": "tool_abc123", "name": "text_analysis"}}}}}

// Tool use input streaming
data: {"event": {"contentBlockDelta": {"contentBlockIndex": 1, "delta": {"toolUse": {"input": "{\"text\": \"hello\"}"}}}}}

// Content block and message completion
data: {"event": {"contentBlockStop": {"contentBlockIndex": 0}}}
data: {"event": {"messageStop": {"stopReason": "end_turn"}}}

// Metadata
data: {"event": {"metadata": {"usage": {"inputTokens": 88, "outputTokens": 30}}}}
```

**Reference:** [Bedrock Converse Stream API](https://boto3.amazonaws.com/v1/documentation/api/latest/reference/services/bedrock-runtime/client/converse_stream.html)

---

## Adding a New Agent Pattern

1. Create `patterns/my-pattern/` with your agent code
2. Set `pattern: my-pattern` in `infra-cdk/config.yaml`

---

## Debugging

Log streaming events in your agent code for debugging:

```python
async for event in agent.stream_async(user_query):
    logger.debug(f"[Streaming Event] {event}")
    yield json.loads(json.dumps(dict(event), default=str))
```