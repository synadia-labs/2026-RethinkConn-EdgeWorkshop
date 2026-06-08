# Lab #12 - Hub remote accesing a stream in leaf


---

Create the streams in the leafs

```sh
nats --context l1 stream add TELEMETRY --subjects="telemetry.*.>" --defaults
nats --context l2 stream add TELEMETRY --subjects="telemetry.*.>" --defaults
nats --context l3 stream add TELEMETRY --subjects="telemetry.*.>" --defaults
```

Some devices in each leaf publish some telemetry

```sh
nats --context l1 pub --jetstream telemetry.device1.temp "1"
nats --context l2 pub --jetstream telemetry.device2.temp "2"
nats --context l3 pub --jetstream telemetry.device3.temp "3"
```

Check the content of the streams:






nats --context l3 consumer create TELEMETRY l3-c0 --pull --ack=explicit --defaults

nats --context hub --js-domain=L3 consumer next TELEMETRY l3-c0 --ack

nats --context hub --js-domain=L3 consumer pause TELEMETRY l3-c0 1h -
