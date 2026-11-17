# Changelog

All notable changes to the SideShift App SDK for iOS are documented here.

## 0.1.0

- Credit installs and opens to the creator link that brought each person in: the SideShift link page, universal links,
  the copied link on first open, Apple's Paste button (`SideShiftPasteButton`) and creator codes (`applyCode`).
- Match people by hashed email, phone or Instagram username (`identify`), after App Tracking Transparency permission by
  default.
- Send App Store purchases, renewals and refunds as Apple signed them (StoreKit 2), checked by SideShift.
- Custom events, consent withdrawal, an offline queue with retries, and a privacy manifest.
