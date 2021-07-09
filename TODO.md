# TODO

## Very Short Term

- [ ] Guard protocol decoder against invalid inputs

## Short Term

- [ ] Implement the missing UDS commands
  - [ ] Control DTC Setting
  - [ ] Communication Control
- [ ] Implement the complete OBD2 command set
- [ ] Implement the missing OBD2 bus protocols

## Mid Term (Swift 5.5 and later)

- [ ] Put the adapter communication handling into a dedicated thread (with higher-than-default priority) and allow a custom queue for dispatching the results?
- [ ] Rewrite most of the parts where we use callbacks in favor of `async`/`await`
  - [ ] `StreamCommandQueue` will become an `actor`
- [ ] `UDS.Message` might actually be a `struct` rather than a `tuple`.
  - Borrow the `ByteBuffer` from `swift-nio` for holding the data?
  - Or at least change our APIs to work with `ArraySlice`s in order to save some of the conversions
- [ ] Prepare for CAN FD
- [ ] Tests, Tests, Tests!

# Questions

- Should we yank the `Adapter`'s `negotiatedProtocol` and move it into the `State` `enum` as `connected(busProtocol)`?
