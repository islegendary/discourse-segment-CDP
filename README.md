# Discourse Segment CDP Plugin

Emits Discourse user and activity events to Segment CDP using the official `analytics-ruby` SDK.

### Currently Supported Events

- `identify` — with flexible user ID strategy
- `track("Signed Up")` — on account creation
- `track("Post Created")`
- `track("Post Liked")`
- `track("Topic Created")`
- `track("Topic Tag Created")`
- `page` — on controller/page-level requests with friendly page names

### Installation

> **Note**: The following installation instructions are examples for a standard Discourse installation. Different hosting providers may have different installation methods. For detailed installation instructions, please refer to the [official Discourse plugin installation guide](https://meta.discourse.org/t/install-plugins-on-a-self-hosted-site/19157).

In Segment, create a `Ruby` source (or use existing) and use the writeKey to configure this plugin in Discourse.

#### New Installation
If you've never used a Segment plugin before:

1. Add the plugin to your Discourse's `app.yml`:
   ```yaml
   hooks:
     after_code:
       - exec:
           cd: $home/plugins
           cmd:
             - mkdir -p plugins
             - git clone https://github.com/islegendary/discourse-segment-CDP.git
   ```

2. Rebuild your Discourse container:
   ```bash
   cd /var/discourse
   ./launcher rebuild app
   ```

3. Go to Settings > Plugins > Segment CDP
4. Add your Segment writeKey and update your settings
5. Enable the plugin

> **Important**: The plugin requires the `analytics-ruby` gem (the official Segment Ruby SDK). This should be automatically installed during the rebuild process in a standard Discourse installation. If you encounter any issues, you may need to manually add this gem to your Discourse's Gemfile.

#### Upgrading from discourse-segment-io-plugin
If you're currently using the old `discourse-segment-io-plugin`, first, follow the installation steps above, but **don't enable** the new plugin until you do the following:

1. Go to Settings > Plugins
2. Disable the old `discourse-segment-io-plugin`
3. In the new plugin, add your Segment writeKey and update your settings
4. Now, Enable the new `Segment CDP` plugin

### Identity Strategy

You can choose how Segment identifies users via the `segment_CDP_user_id_source` site setting:

| Option             | Description                                                         |
|--------------------|---------------------------------------------------------------------|
| `email`            | Uses user email as the `userId`                                     |
| `sso_external_id`  | Uses the user's external ID from SSO if present                     |
| `use_anon`         | Uses a custom, deterministic, 36-character `anonymousId`            |
| `discourse_id`     | Uses the internal Discourse user ID (e.g. `123`)                    |

The `anonymousId` format is:
```
<discourse_id>-dc-<derived_string>
```

This is stable, unique per user, and does not require identifying information like email.

### Page Tracking

The plugin now uses friendly page names for better readability in Segment. Examples include:
- "Latest Topics" instead of "list#latest"
- "Topic View" instead of "topics#show"
- "User Profile" instead of "users#show"
- "Admin Dashboard" instead of "admin#index"

All technical information (controller, action) is still preserved in the properties for debugging.

### 🧪 Debug Logging (Optional)

Enable `segment_CDP_debug_enabled` in site settings to log payloads to the Rails log. This is useful for inspecting or verifying the format of data being sent to Segment.

### 🔁 Backfilling Existing Users

**Note:**
If your site previously used `discourse_id`, and you are switching to Indentity Strategy, Segment will treat these as **new distinct profiles**.

### Contributing

Please see [CONTRIBUTING.md](/CONTRIBUTING.md).

### License

This plugin is © 2025 Donnie W. It is free software, licensed under the terms specified in the [LICENSE](/LICENSE) file.

**Compatibility:** This component provides the same comprehensive tracking as the [discourse-segment-CDP plugin](https://github.com/islegendary/discourse-segment-theme-component) but uses backend server mode tracking instead of frontend javascript tracking.
