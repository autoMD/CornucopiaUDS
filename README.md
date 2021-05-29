# CornucopiaUDS

🐚 The "horn of plenty" – a symbol of abundance.

CornucopiaUDS is an implementation of the _Unified Diagnostic Services_, written in Swift.

## Introduction

This library implements various diagnostic protocols originating in the automotive space, such as:

* __ISO 14229:2020__ : Road vehicles — Unified diagnostic services (UDS)
* __ISO 15765-2:2016__ : Road vehicles — Diagnostic communication over Controller Area Network (DoCAN)
* __SAE J1979:201408__ : Surface Vehicle Standard – (R) E/E Diagnostic Test Modes

## How to use

This is an SPM-compatible package for the use with Xcode (on macOS) or other SPM-compliant consumer (wherever Swift runs on). See the example executable target for a quick primer.

## Motivation

In 2016, I started working on automotive diagnostics. I created the iOS app [OBD2 Expert](https://apps.apple.com/app/obd2-experte/id1142156521), which by now has been downloaded over 500.000 times. I released the underlying framework [LTSupportAutomotive](https://github.com/mickeyl/LTSupportAutomotive), written in Objective-C, as open source.

In 2021, I revisited this domain and have been contracted to implement the UDS protocol on top of the existing library. Pretty soon though it became obvious that there are [too many OBD2-isms](https://github.com/mickeyl/LTSupportAutomotive/issues/35#issuecomment-808062461) in `LTSupportAutomotive` and the implementation of UDS would be overcomplicated. Together with my new focus on Swift, I decided to start from scratch. 

This library is supposed to become the successor of `LTSupportAutomotive`. 

## Hardware

This library is hardware-agnostic and is supposed to work with all kinds of OBD2 adapters. The reference adapter implementation is for generic serial streaming adapters, such as

* ELM327 (and its various clones), **only for OBD2, not suitable for UDS**
* STN11xx-based,
* STN22xx-based,
* UniCarScan 2100 and later,

Support for direct CAN-adapters (such as the Rusoku TouCAN) is also on the way.

For the actual communication, I advise to use [CornucopiaStreams](https://github.com/Cornucopia-Swift/CornucopiaStreams), which transforms WiFi, Bluetooth Classic, BTLE, and TTY into a common stream-based interface.

## Status

### Bus Protocols

Although I have successfully used this library as the base for an ECU reprogramming app, it has _not_ yet been battle-tested. Moreoever, while it has been written with various bus protocols (CAN, K-LINE, J1850, ISO9141, …) in mind, support is only finished for CAN-protocol.

### UDS

UDS is about 50% done – I have started with the necessary calls to upload (TESTER -> ECU) new flash firmwares. The other way is not done yet.

### OBD2

Although I plan to implement the full set of OBD2 calls, the primary focus has been on UDS. I have started to implement a bunch of OBD2 calls to lay out the path for contributors, but did not have time yet to do more.

## Caution! Rocky Road Ahead!

Unfortunately, this library has been written **before** some exciting changes in Swift have been finished and deployed. Car communication is like network communication, hence of _asynchronous nature_. I would have loved to use the forthcoming Swift _concurrency_ support (`async`, `await`, `actor`, …), but it's not complete yet. This means that as soon as Swift 5.5 is available, I'm going to do some fundamental changes to this library.

## Contributions

Feel free to use this under the obligations of the MIT. I welcome all forms of contributions. Stay safe and sound!

