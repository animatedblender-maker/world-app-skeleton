# Performance Contracts & SLOs

**Owner:** Product owner (you)  
**Floor device:** iPhone 11 / iOS 17  
**Rule:** p99 is a product metric. Segment later by app version, OS, device class, country, network.

## User-perceived milestones (required)

| Milestone ID | Definition | Initial target (research) |
|--------------|------------|---------------------------|
| `app_shell_visible` | Root shell (MainTab or Auth) first paint | — |
| `app_start_to_shell` | process start → shell visible | p95 &lt; 800 ms warm; cold TBD |
| `app_start_to_feed_visible` | start → first feed row or skeleton→content | cached p95 &lt; 100 ms perceived |
| `app_start_to_feed_interactive` | start → scroll responds | p95 &lt; 1.5 s cold |
| `feed_nav_first_useful` | tab/back → useful item | warm &lt; 150 ms |
| `reel_swipe_first_frame` | Sparks swipe → first decoded frame | warm p95 &lt; 150 ms |
| `reel_rebuffer_ratio` | rebuffer time / play time | &lt; 2% warm path |
| `message_local_visible` | send tap → bubble on screen | &lt; 50 ms |
| `message_server_ack` | send tap → server ack | p95 &lt; 500 ms good network |
| `search_suggestion` | keystroke → suggestion list update | p95 &lt; 150 ms |
| `profile_interactive` | profile tap → interactive profile | warm &lt; 200 ms |
| `post_detail_usable` | open post → usable detail | warm &lt; 250 ms |
| `optimistic_ui` | like/follow/save visual | &lt; 50 ms |
| `core_api_read` | authenticated GET p95 | &lt; 200 ms server |

## Ship gate

No major surface “done” without:

1. Milestone emission on client  
2. Correlation with backend `trace_id` when network involved  
3. Dashboard (Grafana) owned by you  
4. Explicit regression check before release  

## Instrumentation (code)

- iOS: `PerformanceTelemetry` (see `WorldApp/Services/PerformanceTelemetry.swift`)  
- API: `POST /v1/metrics/batch`  
- Grafana: connect after first metrics land (agent will ask you to create account)
