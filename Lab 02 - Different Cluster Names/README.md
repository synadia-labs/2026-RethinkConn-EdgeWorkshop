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

Outcomes:

- Local subs in the leaf 1 propagate up to the hub, and to the other leafs  (east-west enabled as leafs use different cluster name)
- Subject cardinality matters - subs to different subjects (vs same one) have a bigger impact on the hub AND the leafs

---
