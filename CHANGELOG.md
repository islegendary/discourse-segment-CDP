# Changelog

All notable changes to this plugin will be documented in this file.

## [Unreleased]

### Added
- `segment_CDP_user_id_source` setting for flexible identity logic (`email`, `sso_external_id`, `discourse_id`, `use_anon`)
- Deterministic 36-character `anonymousId` generator with fallback handling
- `segment_CDP_debug_enabled` setting for payload logging
- Full support for:
  - User identify events
  - Custom anonymousId for non-email tracking
  - Page views, post and topic lifecycle events
- Safer error handling in background jobs
- Memoized Segment client for performance
- Friendly page names for better readability in Segment
- Graceful handling of missing writeKey
- Improved installation flow (writeKey first, then enable)

### Changed
- Refactored payload generation into `DiscourseSegmentIdStrategy`
- Modularized `Analytics` client to allow dynamic method handling
- Updated page tracking to use human-readable names
- Improved error handling and logging
- Made plugin start disabled by default
- Added more context to page tracking properties
- Updated repository name to use proper CDP capitalization
- Transferred maintenance to Donnie W
- Optimized track calls to follow Segment's latest specifications
- Improved context object handling for all events

### Deprecated
- Use of `alias` method discouraged per Segment's latest Unify guidance

### Fixed
- NoMethodError when writeKey is missing
- Plugin initialization order issues
- Page tracking error handling
- Duplicate identify calls on user login