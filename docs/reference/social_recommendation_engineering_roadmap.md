# Recommendation & Discovery System for a Next-Generation Social Platform

**Engineering blueprint - production-oriented - version 1.0 - August 2026**

**Audience:** recommendation, backend, data, ML, product, safety, experimentation, SRE, and infrastructure engineering teams.

**Mission:** Build a recommendation platform that can grow from a new social network with sparse data into a global, multi-surface system serving posts, short video, long video, creators, communities, search suggestions, notifications, and ads - without coupling product velocity to one monolithic model.

> Research note: exact architectures used by commercial platforms are proprietary. Public systems from YouTube, Meta, Netflix, and PyTorch/TorchRec are used as reference points; this roadmap is a synthesized engineering design, not a claim that any company implements every listed component.

---

## 0. Executive directives
The platform must optimize durable user value, not raw engagement. The ranking stack must be modular, multiobjective, debuggable, privacy-aware, creator-aware, and safe by construction. Treat recommendation as a product
operating system, not an ML feature.
1. Log every recommendation decision as an impression with enough context to reconstruct what the system knew,
which candidate generators participated, which model/version scored the item, and where the item was placed.
2. Build retrieval and ranking as separate services. Candidate generation must be cheap, broad, and diverse; ranking
may be expensive and precise. This follows the established two-stage industrial pattern described publicly by
YouTube and Instagram Explore [1][2].
3. Make each feed surface an explicit policy configuration over shared platform primitives. Home, Following, Explore,
Reels, long-form video, notifications, creator discovery, and search should not silently share an objective.
4. Use a multi-task model for behavioral outcomes and a policy layer for product value. Do not hide product policy
inside opaque labels.
5. Protect exploration budget. A system that only exploits known interests eventually becomes stale, popularitybiased, and hostile to new creators.
6. Create separate online and offline data quality SLOs. Recommender quality degrades when event semantics drift
even if all services are technically healthy.
7. Never let a ranking model directly bypass safety, legal, eligibility, or hard product constraints. Hard constraints live
outside the learned scorer.
8. Design for cold-start from day one: new user, new creator, new item, new topic, new geography, and new surface.
9. All models require shadowing, canaries, rollback, and feature-level observability. Every model must be
reproducible from immutable training data plus code/config version.
10. Launch complexity only when measurement proves it is needed. Begin with robust baselines; graduate to large
sequential/foundation models only after the event/feature/experiment foundations are reliable.
> **BUILD DECISION:** Adopt a five-plane architecture: (1) event/data plane, (2) feature/representation plane, (3)
candidate/retrieval plane, (4) ranking/policy plane, and (5) experimentation/observability plane. Teams may
evolve each plane independently behind versioned contracts.

## North-star objective hierarchy
Layer

Examples

Rule

Hard guardrails

safety, legal eligibility, blocks/mutes, age
gates, regional restrictions

Never traded against engagement.

User value

explicit satisfaction, retained healthy usage,
successful discovery, follows, saves,
meaningful shares

Primary optimization family.

Session utility

qualified watch/read time, completion,
conversation quality, diversity

Used as intermediate objectives.

Creator ecosystem

distribution fairness, new creator exposure,
creator retention, spam resistance

Constrained product objective, not a single
scalar.

Business value

ad load, conversion, subscription,
marketplace outcomes

Optimized only inside user-value and safety
constraints.



## Reference architecture
Client / API Gateway
|
+--> Context service (session, device, locale, experiments)
+--> Candidate Orchestrator
|-- Follow graph source
|-- ANN embedding retrieval
|-- Content/topic source
|-- Trending/fresh source
|-- Social/creator source
|-- Exploration/new-item source
|-- Search/session-intent source
|
Deduplicate + eligibility
|
Pre-ranker (fast)
|
Heavy multi-task ranker
|
Policy value function
|
Constrained re-ranker
|
Safety / integrity gate
|
Feed assembly + pagination
|
Impression logger
All interactions --> Event bus --> Lake/Warehouse --> Features/Labels --> Training --> Registry --> Serving

## 1. Define the recommendation product contract before training
models
### 1.1 Surfaces are separate products
Create an explicit RecommendationSurface object. It defines candidate sources, eligibility, ranking objective, diversity
constraints, freshness policy, exploration budget, page size, latency budget, and permitted model families. Do not
encode these differences as scattered if-statements.
Surface

Primary intent

Typical candidate mix

Primary success signals

Home

relationship + discovery

following, interest retrieval,
social, fresh, exploration

satisfaction, retained use,
meaningful interactions

Following

recency + relationships

followed creators/accounts

coverage of followed accounts,
low miss rate, freshness

Short video

high-throughput discovery

ANN, sequence/session, creators,
fresh, exploration

qualified watch, completion,
satisfaction, follow/share

Long video

intent + commitment

topic, creator, sequence, searchadjacent

starts, sustained watch,
completion, return

Explore

breadth/discovery

multiple ANN spaces, topic,
graph, trending

novel discovery, saves/follows,
diversity



Search suggestions

explicit intent

lexical + semantic + personalized

successful search, reformulation
reduction

Notifications

high precision interruption

events, relationships,
recommendations

open + downstream value minus
annoyance

Creator suggestions

network growth

graph, content affinity, co-follow

qualified follow and subsequent
interactions

> **BUILD DECISION:** The first production launch should have two distinct feed policies: Following and For
You/Home. Following remains a strong, predictable control surface even when the discovery feed becomes
heavily learned.

### 1.2 Formalize utility as a constrained objective
The heavy ranker predicts calibrated outcomes. A policy layer converts predictions into a platform utility score. Begin
with an interpretable linear or shallow monotonic policy; later replace pieces only when experimentation
demonstrates a gain.
Predictions per (user, item, context):
P(long_view), E[watch_seconds], P(complete), P(like), P(save), P(share),
P(comment_quality), P(follow_creator), P(explicit_positive_feedback),
P(skip_early), P(hide), P(unfollow), P(report), P(session_exit)
Policy score = sum_i w_i(context) * calibrated_prediction_i
+ novelty_bonus
+ creator_ecosystem_adjustment
- repetition_penalty
- predicted_negative_value
Then optimize the ordered list under hard constraints.

### 1.3 Do not use one universal label called engagement
Create a label taxonomy with versioned definitions. Every label has: event source, observation window, censoring
rule, eligibility, delayed-label handling, bot/fraud filters, deduplication, and owner. A changed label definition creates
a new version.

## 2. Event instrumentation: the system begins with trustworthy
behavioral data
### 2.1 Canonical event envelope
event_id: UUID
schema_version: int
event_name: impression | view_start | view_progress | view_end | like | ...
event_time_client: timestamp
event_time_server: timestamp
user_id / anonymous_id
session_id
request_id
surface
item_id, creator_id, item_type


position, page_index
candidate_source_ids[]
retrieval_scores{}
model_versions{}
experiment_assignments{}
device / app_version / locale / coarse_region
network_class
consent_state
integrity_flags{}
payload{}

### 2.2 Events to implement before recommender ML
Family

Minimum events

Notes

Exposure

request, candidate_generated, ranked,
impression, viewport_visible

An impression must mean actual eligible
exposure, not merely returned by API.

Consumption

open, view_start, progress milestones,
view_end, dwell, foreground/background

Capture duration denominator and
interruption reason.

Positive actions

like, save, share, send, follow, subscribe,
comment

Keep action undo events.

Negative actions

skip, hide, not_interested, mute, unfollow,
report, block

Strong negative labels need context.

Navigation

profile_open, hashtag/topic_open, search,
search_click

Useful for intent modeling.

Session

session_start/end, app_background,
notification_open

Needed for retention/session outcomes.

Creator

publish, edit, delete, moderation state

Item eligibility changes over time.

Quality

playback failure, crash, buffering, load
latency

Avoid learning that technical failures mean
user dislike.

> **ENGINEERING WARNING:** Position bias is unavoidable in feed logs. Items ranked near the top receive more
exposure. Log the full serving decision and position so training and evaluation can use randomized buckets,
inverse propensity methods, or controlled exploration rather than naively interpreting clicks as preference.

### 2.3 Data quality gates
• Schema compatibility tests in CI
• Event volume anomaly detection by app version, country, and surface
• Cross-event invariants (impression before click; duration non-negative; unique event_id)
• Clock-skew checks and server-time canonicalization
• Bot/internal-traffic filters
• Late-arriving event policy
• Deletion/consent propagation tests
• Training-serving entity-key consistency checks


## 3. Data architecture and storage contracts
### 3.1 Split streaming and analytical responsibilities
Use an append-only event bus for near-real-time consumers and an immutable analytical store for training/replay. A
practical implementation can use Kafka/Pulsar-compatible streaming, object storage with Parquet/Iceberg/Delta-style
tables, and a warehouse/query engine. Product databases are not the training source of truth.
Clients -> ingestion -> durable event stream --------------------+
|
|
+-> realtime counters/session state
+-> object storage / lakehouse
+-> online features
+-> warehouse / BI
+-> abuse signals
+-> label jobs
+-> training datasets

### 3.2 Dataset invariants
• Point-in-time correctness: a training row may only use information available before its prediction timestamp.
• Deterministic joins: feature computation must have an as-of time and entity key.
• Immutable snapshots: every training run stores dataset snapshot ID and code/config commit.
• Backfills are versioned; never silently overwrite historical semantics.
• Data deletion and retention policies apply to derived features and training snapshots, not only raw tables.

## 4. Feature and representation platform
### 4.1 Feature families
Family

Examples

Freshness

User long-term

topic affinities, creator affinities, language
distribution, historical satisfaction

hours/days

User short-term

last N interactions, session topics, recent
skips, recent search intent

seconds/minutes

Item

age, type, duration, creator, language, topic,
quality signals

minutes/hours

Creator

relationship strength, historical quality, topic
distribution, trust/integrity state

minutes/hours

Cross features

user-topic similarity, user-creator affinity,
user-duration preference

request-time or precomputed

Context

time, device, network, locale, surface, session
depth

request-time

Social graph

follow distance, mutuals, friend interactions

minutes/hours

Content embeddings

text/image/audio/video semantic vectors

publish-time + refresh

Trend

velocity, regional momentum, topic
momentum

seconds/minutes



### 4.2 Feature registry contract
Every feature requires owner, entity keys, dtype, description, source, freshness SLA, TTL, offline computation, online
computation, default, privacy class, allowed surfaces, and monitoring thresholds. Generate training and serving code
from one registry where possible.
> **BUILD DECISION:** Use a dual-store feature platform: offline feature tables for reproducible training and a
low-latency online store for request-time serving. The same feature definition must produce both. This is a
direct defense against training-serving skew.

### 4.3 Embeddings are first-class versioned assets
Do not treat embeddings as anonymous float arrays. Maintain an embedding registry: encoder/model version,
dimension, normalization, entity type, training window, semantic space ID, timestamp, and compatibility. ANN
indexes may only mix vectors from compatible spaces.

## 5. Content understanding pipeline
### 5.1 Generate multimodal representations at publish time
• Text: title, caption, hashtags, OCR text, transcript; detect language; encode with a multilingual text model.
• Image: sample thumbnails/frames; vision encoder; aesthetic/quality features; safety classifiers.
• Audio: speech transcript, language, music/audio embeddings, loudness/quality.
• Video: representative frame sequence, motion features, duration, scene segmentation, optional video encoder.
• Metadata: creator, topic taxonomy, geography if voluntarily/publicly associated, publication time, media format.

### 5.2 Derived semantic objects
Produce item_embedding_content, topic_distribution, language_distribution, entities/keywords, content_quality
vector, safety/integrity labels, and optional modality-specific vectors. Preserve modality vectors even if a fused vector
is generated; retrieval experiments will need them independently.

## 6. Candidate generation: maximize relevant recall before
precision
Retrieval must return a broad, heterogeneous pool. YouTube publicly described a candidate-generation network
followed by a separate ranking network [1]; Instagram Explore has publicly described multi-stage retrieval/ranking
including two-tower neural retrieval [2]. More recent Meta work explores making retrieval itself substantially more
expressive [8].

### 6.1 Mandatory candidate sources
Source

Purpose

Initial implementation

Following/relationship

reliable social relevance

recent items from followed accounts +
affinity ordering

Collaborative ANN

behavioral similarity

two-tower user/item embeddings + ANN
index



Content ANN

semantic discovery/cold start

user/session interest vector against content
embedding index

Sequence/session

current intent

recent interaction encoder or nearestneighbor co-visitation baseline

Trending

fresh/popular discovery

velocity by coarse region/topic with quality
thresholds

Creator affinity

known creator value

creator-user affinity + unseen recent items

Social proof

network discovery

items engaged with by close connections,
privacy-safe aggregation

New-item exploration

creator/item cold start

controlled random/stratified exposure
budget

Editorial/curated

launches/emergencies/special collections

explicit bounded source, never hidden in
ranker

### 6.2 Retrieval orchestration
Each source returns Candidate {
item_id,
source_id,
source_score,
retrieval_reason,
retrieval_model_version,
timestamp
}
Orchestrator:
1. request sources in parallel with per-source timeouts
2. collect up to source quotas
3. deduplicate by item_id while preserving all source attributions
4. apply hard eligibility filters
5. attach lightweight features
6. pre-rank to 500-2,000 candidates
7. send to heavy ranker

### 6.3 ANN engineering
• Maintain separate indexes per semantic space and optionally per region/language when scale requires.
• Choose HNSW/IVF/PQ or managed vector technology based on recall-latency-memory tests; do not choose by
popularity.
• Measure retrieval recall against an expensive offline oracle set.
• Support index snapshots, blue/green swaps, incremental insertions, tombstones, and rollback.
• Keep raw retrieval scores and source identities for debugging and source-level attribution.

## 7. Ranking architecture
### 7.1 Stage A - pre-ranker
The pre-ranker reduces thousands of candidates to hundreds using cheap features and a compact model. Optimize
recall of items the heavy ranker would select, not direct product utility alone.


### 7.2 Stage B - heavy multi-task ranker
Input sparse categorical embeddings, dense numerical features, user/session sequence representation, item/content
representation, cross features, social features, and context. Produce calibrated task heads. News Feed public
engineering material has described multi-task neural networks and embeddings as part of feed ranking [7].
Sparse IDs -> embedding tables ----+
Dense features ---------------------+
User history -> sequence encoder ----+--> shared backbone --> task heads
Item multimodal embedding -----------+
|-> P(long_view)
Cross/context features --------------+
|-> E[watch]
Social/creator features -------------+
|-> P(save/share/follow)
|-> P(hide/report/exit)

### 7.3 Model family progression
Phase

Recommended model

Why

Baseline

logistic/GBDT or small MLP

fast debugging and trustworthy baseline

V1 neural

embedding MLP / DCN-style crosses

learn categorical interactions

V2 sequence

GRU/attention/SASRec-style encoder

model current intent and ordered history

V3 multi-task

shared-bottom + task towers / gating

joint outcomes, better representation sharing

V4 large sequence/foundation

large history model, distillation/caching

capture longer history; Netflix has publicly
described this direction [3]

V5 generative/retrieval fusion

research track only

only after latency, reproducibility, safety,
and cost are controlled

### 7.4 Training design
• Use impression-level examples; positive-only datasets are invalid for ranking.
• Sample negatives with logged exposure context; preserve hard negatives from near-miss candidates.
• Correct or model position/exposure bias using randomized data where feasible.
• Use time-based train/validation/test splits to avoid future leakage.
• Train with delayed outcome windows where labels require future observation.
• Calibrate each task head; ranking policy weights are meaningless if probabilities are badly calibrated.
• Track slice metrics: new users, new items, languages, countries, low-connectivity devices, high/low activity users.
• Store feature importances/attributions or counterfactual diagnostics appropriate to the model family.

## 8. Sequence and session modeling
The system must represent both durable taste and current intent. Keep separate long-term and short-term encoders so
a transient session does not permanently overwrite the user profile.



### 8.1 Sequence tokens
A sequence token should include item/content embedding, action type, dwell/watch bucket, position, timestamp delta,
surface, creator, and optional negative-action marker. Never encode only item IDs if you want cold-start
generalization.

### 8.2 Online state
Maintain a session-state service that updates within seconds. It owns recent interaction sequences and a cached
session embedding. Fall back gracefully to long-term user representation if unavailable.

## 9. Objective design: optimize satisfaction rather than accidental
compulsion
### 9.1 Outcome groups
Group

Signals

Treatment

Consumption quality

qualified dwell/watch, completion, replay

Normalize by content duration and format.

Intentional value

save, share/send, follow, profile open

Often stronger than passive dwell.

Conversation

comment, reply, healthy thread continuation

Require quality/integrity filters.

Explicit satisfaction

surveys, like/dislike, “show more/less”

High-value but sparse.

Negative

early skip, hide, not interested, mute,
unfollow, report

Model separately; reports are not just a
negative click.

Long-term

next-day/week return, successful creator
discovery

Use carefully because attribution is difficult.

Meta reported in 2026 that Facebook Reels work moved beyond likes/watch time by incorporating direct user-interest
feedback, illustrating why explicit satisfaction signals should be a first-class research path [9].

### 9.2 Guard against metric gaming
• Do not optimize raw session length without satisfaction constraints.
• Detect clickbait patterns where predicted click is high but downstream satisfaction is low.
• Add fatigue/repetition features.
• Measure post-session surveys and return behavior, not only in-session actions.
• Maintain holdout groups to detect long-term ecosystem changes.

## 10. Re-ranking and feed composition
The heavy ranker scores items independently; the re-ranker optimizes the list as a whole. This is where diversity,
repetition, fairness/creator constraints, freshness, and exploration become explicit.

### 10.1 Hard constraints
• blocked/muted relationships
• already-deleted or ineligible items


• age/region/legal restrictions
• moderation/safety eligibility
• duplicate media and near-duplicates
• frequency caps and previously-seen policy
• surface-specific format constraints

### 10.2 Soft list constraints
• creator diversity
• topic diversity
• format diversity
• novelty/familiarity balance
• freshness
• new creator exposure
• language relevance
• avoid consecutive near-duplicate embeddings
Greedy constrained rerank (initial implementation):
while output not full:
for each remaining candidate c:
marginal(c) = base_policy_score(c)
+ novelty(c, selected)
+ freshness_bonus(c)
+ exploration_bonus(c)
- creator_repetition(c, selected)
- semantic_repetition(c, selected)
choose highest feasible marginal candidate
update constraint state

## 11. Exploration, cold start, and discovery
### 11.1 Reserve explicit exploration traffic
> **BUILD DECISION:** Start with a bounded exploration budget (for example, a low single-digit percentage of
eligible slots/requests) controlled by surface and risk. The exact percentage is an experiment parameter, not
a permanent constant.

Use stratified exploration so new creators/items compete within quality/safety strata rather than pure uniform
random traffic. Log propensity when randomized selection is used; this creates invaluable unbiased data for
evaluation.

### 11.2 Cold-start policies
Case

Strategy

New user

onboarding interests + locale/language + global/region quality +
rapid session adaptation

Anonymous user

session-only representation + contextual/trending + content


semantics
New item

content embedding retrieval + creator prior + exploration bucket

New creator

content prior + relationship imports/follows if any + exploration with
caps

New topic

semantic encoders + trend detectors + editorial taxonomy bootstrap

## 12. Safety, integrity, and recommendation eligibility
Recommendation eligibility is stricter than mere hosting eligibility. Keep a dedicated eligibility service with reason
codes. Ranking services receive only eligible candidates or must apply a final hard gate immediately before serving.

### 12.1 Controls
• content moderation states and appeals
• spam/engagement bait detection
• bot/fake-account signals
• coordinated manipulation indicators
• misleading metadata/clickbait quality
• age-sensitive content controls
• creator/account trust tiers
• frequency limits for borderline but allowed content
• rapid policy rule propagation without retraining models
> **ENGINEERING WARNING:** Never train the ranking model to “learn” policy enforcement from historical
moderation labels alone. Policy changes must be enforceable immediately and deterministically.

## 13. Creator ecosystem and marketplace health
A social recommender is a two-sided system. User value and creator incentives interact. Add creator-side metrics to
experiments so user-side gains do not quietly concentrate distribution or destroy supply diversity.

### 13.1 Creator metrics
• unique creators receiving qualified impressions
• Gini/concentration of exposure by creator cohort
• new creator time-to-first-qualified-audience
• creator retention and posting frequency
• qualified follower conversion
• exposure efficiency (value per impression)
• appeal/moderation false-positive rates by cohort



## 14. Real-time adaptation and trend systems
### 14.1 Online counters
Maintain streaming windows for 1m/5m/1h/24h event velocity, qualified engagement, negative feedback, and
regional/topic deltas. Trend scores must incorporate expected baseline so large creators do not always dominate.

### 14.2 Freshness service
Store item publish time, first exposure time, acceleration, saturation, and decay. Feed policy can blend evergreen
relevance with time-decayed fresh discovery.

## 15. Training, model registry, and reproducibility
### 15.1 Required artifacts for every model
• training code commit and dependency lock
• dataset snapshot + label version
• feature registry version
• hyperparameters and random seed
• training metrics and slice metrics
• offline evaluation report
• model binary/checkpoint
• calibration artifacts
• serving signature
• shadow/canary results
• model card including intended surfaces and prohibited uses

### 15.2 Embedding-scale infrastructure
Recommendation workloads can be dominated by sparse embedding tables. TorchRec is explicitly designed for
scalable recommender systems and distributed embedding workloads [4][5]. Begin with ordinary PyTorch when scale
is modest; introduce sharded embedding infrastructure only when memory/bandwidth measurements justify it.

## 16. Online serving architecture and latency budget
### 16.1 Service boundaries
Service

Responsibility

Failure mode

Context

session/user/request state

fallback to cached/default context

Candidate orchestrator

parallel source fan-out

drop slow source, preserve minimum pool

Eligibility

hard filtering

fail closed for safety-critical rules

Feature fetch

online features

defaults + freshness flags

Pre-ranker

thousands -> hundreds

fallback heuristic rank


Heavy ranker

multi-task predictions

fallback previous stable model

Re-ranker

list constraints

fallback stable deterministic policy

Feed assembler

pagination/cursors

idempotent cursor recovery

Logger

decision/impression telemetry

buffer/retry; alert on loss

### 16.2 Latency SLO approach
Set an end-to-end p95/p99 budget per surface and allocate it to network, candidate fan-out, feature reads, inference,
reranking, and serialization. Never let a source consume unbounded tail latency. Parallelize candidate sources, cache
item/static features, batch model inference, and precompute item embeddings.
> **BUILD DECISION:** Ship graceful degradation as a first-class feature: each feed request has a deterministic
fallback ladder. A recommender outage must degrade to a safe usable feed, not a blank screen.

## 17. Experimentation, causal measurement, and launch gates
### 17.1 Experiment platform
• stable randomization unit (usually user/account; sometimes cluster/geo for network effects)
• mutually exclusive experiment layers
• server-authoritative assignment
• exposure logging only when treatment can affect the request
• holdouts for long-term measurement
• sample-ratio mismatch alerts
• metric definitions in a central registry
• sequential testing or fixed-horizon rules agreed in advance

### 17.2 Metric hierarchy for launches
Class

Examples

Launch rule

Safety guardrails

report prevalence, harmful-content
exposure, blocks

must not regress beyond predefined bounds

Reliability

latency, errors, empty feed, playback quality

must meet SLO

User value

satisfaction, qualified consumption,
saves/shares/follows

primary success criteria

Retention

D1/D7/D28 or active return

important for mature tests

Diversity

creator/topic entropy, repetition

must remain healthy

Creator

qualified distribution and retention

monitor cohort impacts

Business

revenue/conversion/ad value

secondary to defined guardrails



### 17.3 Offline evaluation is necessary but not sufficient
Track Recall@K/NDCG/MRR/AUC/log loss and calibration, but launch decisions come from controlled online
experiments. Offline data reflects the previous policy and is biased by its exposures.

## 18. Observability and debugging
### 18.1 Every served item must be explainable to engineers
Debug trace for request_id:
- experiment assignments
- context snapshot IDs
- candidate source memberships + source scores
- eligibility decisions/reasons
- feature values + freshness/missingness
- pre-rank score
- heavy-ranker task predictions
- policy score and terms
- reranker penalties/bonuses
- final position
- model/index/config versions
- downstream interaction events

### 18.2 Dashboards
• event ingestion health
• candidate counts by source
• retrieval overlap and source contribution
• feature missingness/staleness
• prediction distributions/calibration drift
• score and rank distribution
• latency by stage
• feed diversity/repetition
• new-user/new-item performance
• safety/integrity exposure
• experiment metric health
• training data drift and embedding drift

## 19. Privacy, deletion, and data minimization
Recommendation systems do not need unlimited retention of raw personal events. Define purpose-limited retention
windows, pseudonymous IDs where possible, coarse rather than precise location for ranking unless explicitly justified,
consent-aware feature eligibility, and deletion propagation through raw events, features, indexes, caches, datasets,
and future training jobs.

### 19.1 Privacy engineering checklist
• data inventory by feature
• purpose and owner for each signal


• retention TTL
• access-control tier
• encryption in transit/at rest
• consent gating
• deletion lineage
• model-training exclusion tests
• privacy review for new sensitive features
• minimum aggregation thresholds for social-proof features

## 20. Phased implementation roadmap
Phase 0 - Instrumentation and deterministic feed (Weeks 0-6)
• Canonical event envelope and impression semantics
• Following feed + simple chronological/quality Explore
• Eligibility service
• warehouse/lake pipeline
• metric registry and experiment assignment skeleton
• initial creator/content metadata pipeline
• replayable request logs
Exit gate: >99% expected core events captured; decision logs reconstruct feeds; latency/reliability SLOs established;
product metrics trusted.

Phase 1 - Baseline personalized ranking (Weeks 6-12)
• hand-engineered user/item/creator features
• co-visitation/collaborative baseline candidate source
• GBDT or compact MLP ranker
• negative signals
• basic reranker for duplicates/creator repetition/freshness
• A/B testing platform
• shadow + canary model deployment
Exit gate: statistically credible user-value lift vs deterministic baseline with no safety/reliability regression.

Phase 2 - Two-tower retrieval + feature platform (Months 3-6)
• offline/online feature registry
• two-tower user/item embeddings
• ANN index service
• content-semantic retrieval for cold start
• embedding registry
• source-level retrieval evaluation


• online session state
Exit gate: retrieval recall improves, feed discovery quality rises, new-item time-to-distribution improves, p95 remains
inside budget.

Phase 3 - Multi-task + sequence ranking (Months 6-10)
• shared multi-task ranker
• calibrated task heads
• sequence/session encoder
• hard-negative mining
• bias-aware training data
• policy-value service
• creator ecosystem metrics
Exit gate: multi-objective gains persist across new/established users and creator cohorts; rollback/fallback tested.

Phase 4 - Exploration and causal learning (Months 9-12)
• logged randomized exploration buckets
• contextual bandit research
• propensity-aware evaluation
• new-creator exploration strata
• long-term holdouts
• explicit satisfaction collection
Exit gate: exploration improves discovery and learning without violating satisfaction/safety constraints.

Phase 5 - Large-scale recommendation foundation (Year 2+)
• long-history sequence/foundation model research
• shared representations across surfaces with surface-specific heads
• distillation into serving models
• larger retrieval models / index-as-model experiments
• GPU/embedding sharding where cost justified
• multi-region model serving and index replication
Netflix publicly described a recommendation foundation model designed to incorporate comprehensive interaction
histories at large scale [3]; Meta has publicly described scaling Instagram to over 1,000 ML models and newer more
expressive retrieval approaches [6][8]. Treat these as mature-scale directions, not launch requirements.

## 21. Team topology and ownership
Team

Owns

RecSys Platform

orchestrator, serving contracts, model gateway, feed assembly

Retrieval

candidate sources, ANN, embedding indexes, recall evaluation

Ranking ML

pre-ranker, heavy ranker, calibration, sequence models


Features & Data

event schemas, feature registry/store, point-in-time datasets

Content Intelligence

text/image/audio/video representations, taxonomy

Experimentation

assignment, metric registry, stats, holdouts

Safety & Integrity

eligibility, abuse models, policy enforcement

Creator Ecosystem

creator objectives, cold start, supply health

ML Infrastructure

training platform, registry, deployment, accelerators

SRE/Observability

SLOs, tracing, capacity, incident response

Privacy/Security

data governance, access, deletion, privacy review

Product/Research

objective definitions, surveys, roadmap, long-term research

### 21.1 Interface rule
Teams own APIs and measurable contracts, not hidden database dependencies. Candidate sources return a common
Candidate object; ranking models use a versioned feature schema; experiments consume centrally defined metrics;
eligibility returns reason-coded decisions.

## 22. Engineering backlog by workstream
Data / telemetry
• event schema registry
• mobile/web SDK instrumentation
• server impression logger
• stream validation
• lakehouse tables
• point-in-time dataset builder
• data quality monitors
• deletion propagation

Feature / representation
• feature registry DSL/config
• offline materialization
• online KV store
• feature freshness metadata
• embedding registry
• content encoders
• session state service
• trend aggregations


Retrieval / ranking
• candidate orchestrator
• source plugin API
• ANN service
• pre-ranker inference
• heavy ranker inference
• policy scorer
• reranker
• fallback ladder
• debug trace API

ML lifecycle
• training pipelines
• model registry
• offline evaluator
• calibration pipeline
• shadow deploy
• canary deploy
• rollback
• drift monitoring
• scheduled/retriggered retraining

Experiment / product
• assignment service
• metric catalog
• SRM checks
• experiment dashboard
• long-term holdout
• survey system
• creator cohort reporting
• safety guardrail dashboard

## 23. Recommended core schemas
### 23.1 Recommendation request
RecommendationRequest {
request_id, user_id/anonymous_id, session_id,
surface, page_size, cursor,
device_context, locale, coarse_region,
experiment_assignments, consent_state,
client_capabilities


}

### 23.2 Candidate
Candidate {
item_id,
sources: [{source_id, source_score, reason, version}],
eligibility_version,
retrieval_timestamp
}

### 23.3 Scored candidate
ScoredCandidate {
candidate,
predictions: {task_name: value},
calibrated_predictions: {...},
policy_components: {...},
base_score,
feature_snapshot_id,
model_version
}

### 23.4 Final decision
ServeDecision {
request_id,
ordered_items: [{item_id, final_position, final_score, rerank_reasons}],
model_versions, index_versions, config_version,
candidate_source_status,
latency_breakdown,
decision_timestamp
}

## 24. Feature engineering catalogue
Entity

Feature

Implementation note

User

topic affinity vector

decayed weighted actions; separate
positive/negative affinities

User

creator affinity

recency/frequency + qualified actions

User

duration preference

conditional on format/topic

User

session intent embedding

sequence encoder or weighted recent
content vectors

Item

content embedding

multimodal; fixed versioned space

Item

freshness

log age + surface-specific decay

Item

quality prior

smoothed rate, confidence-aware; avoid lowsample volatility



Item

velocity

observed vs expected momentum

Creator

relationship strength

user-creator interaction history

Creator

quality/trust prior

separate from popularity

Cross

semantic similarity

user/session vs item embedding

Cross

novelty

distance from recently consumed cluster

Context

session depth

behavior changes late in session

Context

network/device

avoid ranking media likely to fail playback

Social

close connections engaged

privacy-safe thresholded aggregation

Negative

recent topic fatigue

count/decay of similar exposures and skips

## 25. Offline and online metric specification
### 25.1 Retrieval
• Recall@K against later high-value interactions
• candidate source coverage
• unique creator/topic coverage
• new-item recall
• source overlap/Jaccard
• latency and timeout rate

### 25.2 Ranking
• NDCG@K / Recall@K for task-weighted relevance
• log loss and Brier/calibration error per task
• pairwise accuracy
• slice metrics
• counterfactual/randomized evaluation where available

### 25.3 Online
• qualified consumption
• save/share/follow
• explicit satisfaction
• negative feedback
• retention
• creator diversity/concentration
• topic/creator repetition
• safety prevalence


• latency/error/empty-feed
• new-user activation and new-item discovery

## 26. Recommender incident playbook
Incident

Immediate action

Diagnosis

Feed quality collapse

rollback model/config; use stable fallback

prediction drift, feature freshness, candidate
source loss

Latency spike

disable slow source/heavy model tier

stage latency trace, cache miss, ANN/index
health

Empty feeds

fallback to following/trending

eligibility outage, cursor bug, source failures

Harmful content spike

tighten eligibility rule immediately

policy/model lag, abuse campaign,
moderation state propagation

Popularity runaway

increase source/diversity constraints;
rollback

feature scaling, feedback loop, trend bug

New creator starvation

activate exploration baseline

ANN cold-start, quality prior bias, candidate
quotas

Event logging loss

freeze retraining; alert experiments

SDK/version, ingestion, schema rejection

## 27. Research agenda after the production baseline is stable
• Long-horizon value estimation and causal retention attribution
• Large sequence/foundation recommendation models
• Generative retrieval / learned indexes
• Cross-surface representation sharing without objective leakage
• Multi-objective constrained optimization
• Counterfactual learning from logged bandit feedback
• Graph neural recommendation for social discovery
• Multimodal item/user representations
• Privacy-preserving personalization and on-device adaptation
• Efficient distillation, quantization, caching, and speculative ranking
• Robustness against adversarial creators and feedback manipulation
• Fair exposure and marketplace optimization under creator constraints

## 28. Production launch checklist
• ☐ Event semantics documented and validated
• ☐ Training dataset is point-in-time correct
• ☐ Feature defaults and missingness behavior tested
• ☐ Model reproducible from registry artifacts


• ☐ Shadow traffic results acceptable
• ☐ Canary rollback exercised
• ☐ Candidate source timeouts configured
• ☐ Eligibility fail mode reviewed by Safety
• ☐ Feature store outage fallback tested
• ☐ ANN index blue/green swap tested
• ☐ Calibration validated on major slices
• ☐ Reranker constraints unit-tested
• ☐ Experiment assignment and exposure logging verified
• ☐ Safety/user/creator guardrails defined before launch
• ☐ Dashboards and alerts live
• ☐ On-call runbook exists
• ☐ Privacy/deletion review complete
• ☐ Capacity test covers p99 and regional failover
• ☐ Fallback feed verified
• ☐ Post-launch owner and decision date assigned

Appendix A. Suggested initial technology choices
These are defaults, not mandates. Choose technologies already operated well by the organization when they satisfy the
contract.
Layer

Pragmatic starting point

Scale-up path

Events

Kafka/Pulsar-compatible durable log

multi-region replicated streams

Lake

object storage + Parquet/Iceberg/Delta

partition/compaction governance

Warehouse

columnar analytical warehouse

federated query + semantic metric layer

Online features

Redis/KeyDB/Dynamo-style KV

purpose-built feature store

Training

PyTorch

TorchRec/distributed embeddings when
necessary

ANN

FAISS/HNSW-compatible service or managed
vector DB

sharded replicated ANN / learned retrieval

Serving

containerized CPU/GPU inference

dynamic batching, quantization, dedicated
accelerators

Registry

MLflow-like model registry + artifact store

integrated governance/model cards

Orchestration

Airflow/Dagster/Argo-style workflows

event-driven retraining

Observability

OpenTelemetry + metrics/logs/traces

model-specific drift/feature observability



Appendix B. First 12 experiments
Experiment

Purpose

Chronological vs simple personalized Home

prove personalization value

Add negative skip/hide features

reduce obvious dissatisfaction

Creator repetition penalty

improve list diversity without hurting utility

Content-semantic retrieval source

improve new-item cold start

Two-tower collaborative retrieval

improve candidate recall

Session intent features

capture short-term interest shifts

Multi-task vs single-task engagement

improve balanced outcomes

Calibrated policy weights

make objective tradeoffs explicit

New-creator exploration bucket

improve supply discovery

Freshness decay tuning

balance evergreen and new content

Explicit “show more/less” feedback

collect higher-quality preference data

Long-term holdout

measure retention/ecosystem effects

Appendix C. References and public engineering anchors
[1] Covington, Adams, Sargin (2016). Deep Neural Networks for YouTube Recommendations. Google Research.
https://research.google/pubs/deep-neural-networks-for-youtube-recommendations/
[2] Meta Engineering (2023). Scaling the Instagram Explore recommendations system.
https://engineering.fb.com/2023/08/09/ml-applications/scaling-instagram-explore-recommendations-system/
[3] Netflix Technology Blog (2025). Foundation Model for Personalized Recommendation. https://netflixtechblog.com/foundation-model-forpersonalized-recommendation-1a0bd8e02d39
[4] PyTorch Tutorials. Introduction to TorchRec. https://docs.pytorch.org/tutorials/intermediate/torchrec_intro_tutorial.html
[5] PyTorch (2025). Scaling Recommendation Systems Training to Thousands of GPUs with 2D Sparse Parallelism.
https://pytorch.org/blog/scaling-recommendation-2d-sparse-parallelism/
[6] Meta Engineering (2025). Journey to 1000 models: Scaling Instagram’s recommendation system.
https://engineering.fb.com/2025/05/21/production-engineering/journey-to-1000-models-scaling-instagrams-recommendation-system/
[7] Meta Engineering (2021). News Feed ranking, powered by machine learning. https://engineering.fb.com/2021/01/26/core-infra/news-feedranking/
[8] Meta Engineering (2026). SilverTorch: Index as Model - A New Retrieval Paradigm for Recommendation Systems.
https://engineering.fb.com/2026/05/26/ml-applications/silvertorch-index-as-model-new-retrieval-paradigm-recommendation-systems/
[9] Meta Engineering (2026). Adapting the Facebook Reels RecSys AI Model Based on User Feedback. https://engineering.fb.com/2026/01/14/mlapplications/adapting-the-facebook-reels-recsys-ai-model-based-on-user-feedback/
[10] Meta Engineering (2024). Meta Andromeda: next-generation personalized ads retrieval engine.
https://engineering.fb.com/2024/12/02/production-engineering/meta-andromeda-advantage-automation-next-gen-personalized-ads-retrievalengine/



Appendix D. Final directive to the engineering organization
Do not begin by asking which neural network is fashionable. Begin by making recommendation decisions observable,
reproducible, measurable, and reversible. Build high-quality event semantics. Build multiple independent candidate
sources. Build a reliable feature/representation layer. Establish a simple model that can be beaten. Then add deep
retrieval, sequence models, and multi-task learning one measured step at a time.
The enduring competitive advantage will come from the feedback system: better signals, faster experiments, stronger
content understanding, safer exploration, better creator matching, lower-latency infrastructure, and a culture that can
distinguish a real user-value gain from a metric artifact. The model is one component of that system.
