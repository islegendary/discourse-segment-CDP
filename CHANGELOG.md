# Changelog

All notable changes to this plugin will be documented in this file.

## [Unreleased]

### Added
- `segment_cdp_user_id_source` setting for flexible identity logic (`email`, `sso_external_id`, `discourse_id`, `use_anon`)
- Deterministic 36-character `anonymousId` generator with fallback handling
- `segment_cdp_debug_enabled` setting for payload logging
- Full support for:
  - User identify events
  - Custom anonymousId for non-email tracking
  - Page views, post and topic lifecycle events
- Safer error handling in background jobs
- Memoized Segment client for performance
- Friendly page names for better readability in Segment
- Graceful handling of missing write key
- Improved installation flow (write key first, then enable)

### Changed
- Refactored payload generation into `DiscourseSegmentIdStrategy`
- Modularized `Analytics` client to allow dynamic method handling
- Updated page tracking to use human-readable names
- Improved error handling and logging
- Made plugin start disabled by default
- Added more context to page tracking properties

### Deprecated
- Use of `alias` method discouraged per Segment's latest Unify guidance

### Fixed
- NoMethodError when write key is missing
- Plugin initialization order issues
- Page tracking error handling