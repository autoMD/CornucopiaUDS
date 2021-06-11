# TODO

## Very Short Term

- [ ] Guard protocol decoder against invalid inputs

## Short Term

- [ ] Implement the missing bus protocols
- [ ] Implement the missing UDS commands
- [ ] Implement the complete OBD2 command set

## Mid Term (Swift 5.5 and later)

- [ ] Put the adapter communication handling into a dedicated thread (with higher-than-default priority) and allow a custom queue for dispatching the results?
- [ ] Rewrite most of the parts where we use callbacks in favor of `async`/`await`
- [ ] `UDS.Message` might actually be a `struct` rather than a `tuple`.
  - Borrow the `ByteBuffer` from `swift-nio` for holding the data
- [ ] Prepare for CAN FD
- [ ] Tests, Tests, Tests!

# Questions

- Should we yank the `Adapter`'s `negotiatedProtocol` and move it into the `State` `enum` as `connected(busProtocol)`?
