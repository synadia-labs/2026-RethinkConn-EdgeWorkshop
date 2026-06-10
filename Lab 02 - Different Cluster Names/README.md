# Lab #2 - Leafs using different cluster name

- Repeat of Lab #1 but using different cluster names for the leafs
- East-west traffic will be enabled
- Basic subscription analysis (impact of leaf subs in hub and the other leafs)

Updated configs but same setup and test commands as Lab #1.

---

## Subscription test

Outcomes:

- East-west traffic enabled throught the hub

---

## Subscription analysis

Create a subscription from the hub and each leaf:

```sh
$ ./demo.sh
```

Or

```sh
nats --context hub sub foo.hub
nats --context l1 sub foo.l1
nats --context l2 sub foo.l2
nats --context l3 sub foo.l3
```

List the subscriptions subjects in the hub (local subs only, will not show those received from leaf):

```sh
curl -s "localhost:8222/subsz?subs=1" |
jq -r '
  .subscriptions_list[]
  | select(.account == "APP")
  | .subject
' | sort
```

List the subscriptions subjects in the hub, that came from the leafs:

```sh
curl -s "localhost:8222/leafz?subs=1" |
jq -r '
  .leafs[]
  | .subscriptions_list[]
' | sort
```

List the subscriptions subjects in the leaf 1 (:8232), that came from the hub:

```sh
curl -s "localhost:8242/leafz?subs=1" |
jq -r '
  .leafs[]
  | .subscriptions_list[]
' | sort
```

The subscriptions from the hub and other leaf nodes should be present.

Outcomes:

- Local subs in the leaf 1 propagate up to the hub, and to the other leafs  (east-west enabled as leafs use different cluster name)
- Subject cardinality matters - subs to different subjects (vs same one) have a bigger impact on the hub AND the leafs

---
