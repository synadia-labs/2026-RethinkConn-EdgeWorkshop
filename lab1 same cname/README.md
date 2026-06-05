# Lab #1 - Leafs using same cluster name

- Hub and 3 leafs, minimal setup, same cluster name in leafs.
- East-west traffic will be disabled.
- Basic subscription analysis (impact of leaf subs in hub)

---

## Setup notes

Start the hub and 3 leaf nodes (follow notes in Lab #0)

---

## Subscription test

Tests

```sh
nats --context hub sub foo
nats --context l1 sub foo
nats --context l2 sub foo
nats --context l3 sub foo

nats --context hub pub foo "hello from hub"
nats --context l1 pub foo "hello from leaf 1"
nats --context l2 pub foo "hello from leaf 2"
nats --context l3 pub foo "hello from leaf 3"
```

Outcomes:

- no east-west traffic
- North-south and south-north ok

---

## Subscription analysis

With the hub and leaf servers up and running, compare 3 scenarios:

1. No clients subscribing anywhere
2. A bunch of clients on a leaf, subscribing to the same subject
3. A bunch of clients on a leaf, subscribing to different subjects

For #2 we can start 100 subs in leaf 1, same subject foo:

```sh
nats --context l1 bench sub foo --clients=100 --no-progress
```

For #3, 100 service requesters will create a bunch of different inboxes where they expect a response:

```sh
# fake no-responder service(needed to avoid no-responders fast fail)
nats --context l1 sub foo  # blocks!
# start 100 subs, set a long timeout to keep them holding up
nats --context l1 bench service request foo --timeout=1000s --clients=100 --no-progress
```

Compare before & after for each scenario, using the following commands:

Check number of subscriptions (totals for local+gateways+remotes):

```sh
# hub
curl -s localhost:8222/subsz | jq .num_subscriptions
# leaf 1
curl -s localhost:8232/subsz | jq .num_subscriptions
# leaf 2
curl -s localhost:8242/subsz | jq .num_subscriptions
# leaf 3
curl -s localhost:8252/subsz | jq .num_subscriptions
```

List the subscriptions subjects in the hub (local subs only, will not show those received from leaf):

```sh
curl -s "localhost:8222/subsz?subs=1" |
jq -r '
  .subscriptions_list[]
  | select(.account == "APP")
  | .subject
'
```

List the subscriptions subjects in the hub, that came from the leafs:

```sh
curl -s "localhost:8222/leafz?subs=1" | 
jq -r '
  .leafs[]
  | .subscriptions_list[]
'
```

List the sub subjects in the leaf 1 (:8232):

```sh
curl -s "localhost:8232/subsz?subs=1" |
jq -r '
  .subscriptions_list[]
  | select(.account == "EDGE")
  | .subject
'
```

List the subscriptions subjects in the leaf 2 (:8242), that came from the hub:

```sh
curl -s "localhost:8242/leafz?subs=1" | 
jq -r '
  .leafs[]
  | .subscriptions_list[]
'
```

Outcomes:

- Local subs in the leaf 1 propagate up to the hub, but not the the other leafs (east-west disabled as leafs use same cluster name)
- Subject cardinality matters - subs to different subjects (vs same one) have bigger impact on the hub.

---
