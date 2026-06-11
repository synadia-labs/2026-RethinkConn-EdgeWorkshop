# Subscription Load Tool

Creates many unique subscriptions against a NATS server and holds them open.
This is useful when a lab needs visible subject-interest growth in
`scripts/monitor.sh`.

```sh
go run tools/subscription-load/main.go --node=l1 --count=1000 --prefix=edge.device
```

Subjects are created as:

```text
edge.device.000001.status
edge.device.000002.status
...
```

Options:

```sh
go run tools/subscription-load/main.go --help
```

The default node is `l1`. Node names resolve through matching NATS CLI contexts
when present, with workshop defaults for `hub`, `l1`, `l2`, and `l3`. Use
`--url` for an explicit server URL.
