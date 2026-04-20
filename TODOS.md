# TODOS

## Before v1.1

### [TODO-1] ~~Research Cal AI App Store removal~~ — RESOLVED ✓

**Finding (April 2026):** Cal AI was removed due to **aggressive paywall dark patterns**, not camera-based AI food estimation as a feature category. The AI photo-to-calories feature itself is not the policy violation. Apple guideline 3.1.x (subscription manipulation, misleading trial terms) is the likely cause.

**Implications:**
- Camera meal estimation via AI photo is **safe to ship on App Store** as long as paywall is clean
- Our paywall (blurred card + honest trial CTA, no fake countdown timers) does not replicate Cal AI's violation
- No special disclaimers or framing required for the camera feature itself
- Camera estimation remains v1.1 scope for practical reasons (engineering complexity, API cost model), not policy

**Not blocking anything.**
# TODOS

## Pepper: Supabase Edge Function API Proxy
**What:** Replace xcconfig Claude API key with a Supabase Edge Function that proxies POST /v1/messages.
**Why:** API key embedded in the app binary is extractable. Required before App Store submission.
**How to apply:** Create `supabase/functions/pepper-proxy/index.ts`. iOS calls Supabase function URL with Bearer session token. Function validates Supabase auth, forwards request to Anthropic, returns response. Rate limit per userId.
**Depends on:** Nothing — Supabase already configured at sgbszuimvqxzqvmgvyrn.supabase.co
**Blocked by:** None. Can be done in parallel with Pepper feature work.

## Pepper: create_workout_routine Tool (Phase 2)
**What:** Implement the `create_workout_routine` Pepper tool.
**Why:** Lets users say "create a push day with bench, overhead press, and tricep dips" and have Pepper build the routine in the app.
**How to apply:** After the other 5 write tools are stable and tested. Models already exist: LocalRoutine + LocalRoutineExercise in SwiftDataModels.swift.
**Depends on:** Core Pepper agentic architecture (PepperService, tool execution flow).
**Effort:** 2-3 days of feature work.
