const std = @import("std");
const log = std.log.scoped(.main);
const json = std.json;
const stdout = std.io.getStdOut().writer();

pub fn main() !void {
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .{};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        try PrintHelpMessageAndExit();
        return;
    }

    ProcessCMD(args, allocator) catch {};
}

fn ProcessCMD(processArgs: [][:0]u8, allocator: std.mem.Allocator) !void {
    const username = processArgs[1];
    var buf: [256]u8 = undefined;
    const url = try std.fmt.bufPrint(&buf, "https://api.github.com/users/{s}/events", .{username});

    var httpClient = std.http.Client{ .allocator = std.heap.page_allocator };
    defer httpClient.deinit();

    var body = std.ArrayList(u8).init(allocator);
    defer body.deinit();

    const response = try httpClient.fetch(.{
        .method = .GET,
        .location = .{ .url = url },
        .response_storage = .{ .dynamic = &body },
    });
    const bodySlice = try body.toOwnedSlice();
    defer allocator.free(bodySlice);

    if (response.status == .not_found) {
        log.err("User {s} was not found.", .{username});
        return error.HttpError;
    }

    if (response.status != .ok) {
        log.err("An error has occurred during requesting {s} events.", .{username});
        return error.HttpError;
    }

    if (bodySlice.len == 2 or bodySlice.len == 0) {
        log.err("User {s} has no events.", .{username});
    } else {
        var jsonData = json.parseFromSlice([]Event, allocator, bodySlice, .{ .ignore_unknown_fields = true }) catch |err| {
            log.err("An error has occurred during parsing {s} events: {any}.", .{ username, err });
            return;
        };
        defer jsonData.deinit();
        log.info("User {s} events: {d}", .{ username, jsonData.value.len });

        for (jsonData.value) |event| {
            // if (std.mem.eql(u8, event.type, "CommitCommentEvent")) {
            //     stdout.print("Commented on {s} commit\n", .{event.payload.commit}) catch {};
            // }
            if (std.mem.eql(u8, event.type, "CreateEvent")) {
                stdout.print("Created {s} | branch {?s}\n", .{ event.repo.name, event.payload.ref }) catch {};
            } else if (std.mem.eql(u8, event.type, "DeleteEvent")) {
                stdout.print("Deleted {s} | branch {?s}\n", .{ event.repo.name, event.payload.ref }) catch {};
            } else if (std.mem.eql(u8, event.type, "ForkEvent")) {
                stdout.print("Forked {s}\n", .{event.repo.name}) catch {};
            }
            // else if (std.mem.eql(u8, event.type, "GollumEvent")) {
            //     stdout.print("Edited {s} pages\n", .{event.payload.pages.?.len}) catch {};
            // }
            // else if (std.mem.eql(u8, event.type, "IssueCommentEvent")) {
            //     stdout.print("Commented on {s} issue\n", .{event.payload.issue.?.title}) catch {};
            // }
            // else if (std.mem.eql(u8, event.type, "IssuesEvent")) {
            //     stdout.print("Created {s} issue\n", .{event.payload.issue.?.title}) catch {};
            // }
            else if (std.mem.eql(u8, event.type, "MemberEvent")) {
                stdout.print("Added {s} to {s}\n", .{ event.actor.login, event.repo.name }) catch {};
            } else if (std.mem.eql(u8, event.type, "PublicEvent")) {
                stdout.print("Made {s} public\n", .{event.repo.name}) catch {};
            } else if (std.mem.eql(u8, event.type, "PullRequestEvent")) {
                stdout.print("Created {s} pull request on {s}\n", .{ event.payload.pull_request.?.title, event.repo.name }) catch {};
            } else if (std.mem.eql(u8, event.type, "PullRequestReviewEvent")) {
                stdout.print("Reviewed {s} pull request\n", .{event.payload.pull_request.?.title}) catch {};
            } else if (std.mem.eql(u8, event.type, "PullRequestReviewCommentEvent")) {
                stdout.print("Commented on {s} pull request\n", .{event.payload.pull_request.?.title}) catch {};
            } else if (std.mem.eql(u8, event.type, "PullRequestReviewThreadEvent")) {
                stdout.print("Commented on {s} pull request\n", .{event.payload.pull_request.?.title}) catch {};
            } else if (std.mem.eql(u8, event.type, "PushEvent")) {
                stdout.print("Pushed {d} commits to {s}\n", .{ event.payload.commits.?.len, event.repo.name }) catch {};
            }
            // else if (std.mem.eql(u8, event.type, "ReleaseEvent")) {
            //     stdout.print("Released {s}\n", .{event.payload.release.?.name}) catch {};
            // }
            // else if (std.mem.eql(u8, event.type, "SponsorshipEvent")) {
            //     stdout.print("Sponsored {s}\n", .{event.payload.sponsorship.?.sponsor.login}) catch {};
            // }
            else if (std.mem.eql(u8, event.type, "WatchEvent")) {
                stdout.print("Watched {s}\n", .{event.repo.name}) catch {};
            } else {
                stdout.print("Unknown event type: {s}\n", .{event.type}) catch {};
            }
        }
    }
}

fn PrintHelpMessageAndExit() !void {
    const helpMessage =
        \\ help - show this help
        \\ <username> - looks up user's info
    ;
    try stdout.print("{s}\n", .{helpMessage});
    std.process.exit(0);
}

pub const Event = struct {
    id: []const u8,
    type: []const u8,
    actor: struct {
        id: i64,
        login: []const u8,
        display_login: []const u8,
        gravatar_id: []const u8,
        url: []const u8,
        avatar_url: []const u8,
    },
    repo: struct {
        id: i64,
        name: []const u8,
        url: []const u8,
    },
    payload: struct {
        ref: ?[]const u8 = null,
        ref_type: ?[]const u8 = null,
        pusher_type: ?[]const u8 = null,
        repository_id: ?i64 = null,
        push_id: ?i64 = null,
        size: ?i64 = null,
        distinct_size: ?i64 = null,
        head: ?[]const u8 = null,
        before: ?[]const u8 = null,
        commits: ?[]const struct {
            sha: []const u8,
            author: struct {
                email: []const u8,
                name: []const u8,
            },
            message: []const u8,
            distinct: bool,
            url: []const u8,
        } = null,
        action: ?[]const u8 = null,
        number: ?i64 = null,
        pull_request: ?struct {
            url: []const u8,
            id: i64,
            node_id: []const u8,
            html_url: []const u8,
            diff_url: []const u8,
            patch_url: []const u8,
            issue_url: []const u8,
            number: i64,
            state: []const u8,
            locked: bool,
            title: []const u8,
            user: struct {
                login: []const u8,
                id: i64,
                node_id: []const u8,
                avatar_url: []const u8,
                gravatar_id: []const u8,
                url: []const u8,
                html_url: []const u8,
                followers_url: []const u8,
                following_url: []const u8,
                gists_url: []const u8,
                starred_url: []const u8,
                subscriptions_url: []const u8,
                organizations_url: []const u8,
                repos_url: []const u8,
                events_url: []const u8,
                received_events_url: []const u8,
                type: []const u8,
                site_admin: bool,
            },
            body: ?u0,
            created_at: []const u8,
            updated_at: []const u8,
            closed_at: ?[]const u8,
            merged_at: ?[]const u8,
            merge_commit_sha: ?[]const u8,
            assignee: ?u0,
            assignees: []const ?u0,
            requested_reviewers: []const ?u0,
            requested_teams: []const ?u0,
            labels: []const ?u0,
            milestone: ?u0,
            draft: bool,
            commits_url: []const u8,
            review_comments_url: []const u8,
            review_comment_url: []const u8,
            comments_url: []const u8,
            statuses_url: []const u8,
            head: struct {
                label: []const u8,
                ref: []const u8,
                sha: []const u8,
                user: struct {
                    login: []const u8,
                    id: i64,
                    node_id: []const u8,
                    avatar_url: []const u8,
                    gravatar_id: []const u8,
                    url: []const u8,
                    html_url: []const u8,
                    followers_url: []const u8,
                    following_url: []const u8,
                    gists_url: []const u8,
                    starred_url: []const u8,
                    subscriptions_url: []const u8,
                    organizations_url: []const u8,
                    repos_url: []const u8,
                    events_url: []const u8,
                    received_events_url: []const u8,
                    type: []const u8,
                    site_admin: bool,
                },
                repo: struct {
                    id: i64,
                    node_id: []const u8,
                    name: []const u8,
                    full_name: []const u8,
                    private: bool,
                },
            },
            base: struct {
                label: []const u8,
                ref: []const u8,
                sha: []const u8,
                user: struct {
                    login: []const u8,
                    id: i64,
                    node_id: []const u8,
                    avatar_url: []const u8,
                    gravatar_id: []const u8,
                    url: []const u8,
                    html_url: []const u8,
                    followers_url: []const u8,
                    following_url: []const u8,
                    gists_url: []const u8,
                    starred_url: []const u8,
                    subscriptions_url: []const u8,
                    organizations_url: []const u8,
                    repos_url: []const u8,
                    events_url: []const u8,
                    received_events_url: []const u8,
                    type: []const u8,
                    site_admin: bool,
                },
                repo: struct {
                    id: i64,
                    node_id: []const u8,
                    name: []const u8,
                    full_name: []const u8,
                    private: bool,
                },
            },
            _links: struct {
                self: struct {
                    href: []const u8,
                },
                html: struct {
                    href: []const u8,
                },
                issue: struct {
                    href: []const u8,
                },
                comments: struct {
                    href: []const u8,
                },
                review_comments: struct {
                    href: []const u8,
                },
                review_comment: struct {
                    href: []const u8,
                },
                commits: struct {
                    href: []const u8,
                },
                statuses: struct {
                    href: []const u8,
                },
            },
            author_association: []const u8,
            auto_merge: ?u0,
            active_lock_reason: ?u0,
            merged: bool,
            mergeable: ?u0,
            rebaseable: ?u0,
            mergeable_state: []const u8,
            merged_by: ?struct {
                login: []const u8,
                id: i64,
                node_id: []const u8,
                avatar_url: []const u8,
                gravatar_id: []const u8,
                url: []const u8,
                html_url: []const u8,
                followers_url: []const u8,
                following_url: []const u8,
                gists_url: []const u8,
                starred_url: []const u8,
                subscriptions_url: []const u8,
                organizations_url: []const u8,
                repos_url: []const u8,
                events_url: []const u8,
                received_events_url: []const u8,
                type: []const u8,
                site_admin: bool,
            },
            comments: i64,
            review_comments: i64,
            maintainer_can_modify: bool,
            commits: i64,
            additions: i64,
            deletions: i64,
            changed_files: i64,
        } = null,
        master_branch: ?[]const u8 = null,
        description: ?[]const u8 = null,
        forkee: ?struct {
            id: i64,
            node_id: []const u8,
            name: []const u8,
            full_name: []const u8,
            private: bool,
            owner: struct {
                login: []const u8,
                id: i64,
                node_id: []const u8,
                avatar_url: []const u8,
                gravatar_id: []const u8,
                url: []const u8,
                html_url: []const u8,
                followers_url: []const u8,
                following_url: []const u8,
                gists_url: []const u8,
                starred_url: []const u8,
                subscriptions_url: []const u8,
                organizations_url: []const u8,
                repos_url: []const u8,
                events_url: []const u8,
                received_events_url: []const u8,
                type: []const u8,
                site_admin: bool,
            },
            html_url: []const u8,
            description: []const u8,
            fork: bool,
            url: []const u8,
            forks_url: []const u8,
            keys_url: []const u8,
            collaborators_url: []const u8,
            teams_url: []const u8,
            hooks_url: []const u8,
            issue_events_url: []const u8,
            events_url: []const u8,
            assignees_url: []const u8,
            branches_url: []const u8,
            tags_url: []const u8,
            blobs_url: []const u8,
            git_tags_url: []const u8,
            git_refs_url: []const u8,
            trees_url: []const u8,
            statuses_url: []const u8,
            languages_url: []const u8,
            stargazers_url: []const u8,
            contributors_url: []const u8,
            subscribers_url: []const u8,
            subscription_url: []const u8,
            commits_url: []const u8,
            git_commits_url: []const u8,
            comments_url: []const u8,
            issue_comment_url: []const u8,
            contents_url: []const u8,
            compare_url: []const u8,
            merges_url: []const u8,
            archive_url: []const u8,
            downloads_url: []const u8,
            issues_url: []const u8,
            pulls_url: []const u8,
            milestones_url: []const u8,
            notifications_url: []const u8,
            labels_url: []const u8,
            releases_url: []const u8,
            deployments_url: []const u8,
            created_at: []const u8,
            updated_at: []const u8,
            pushed_at: []const u8,
            git_url: []const u8,
            ssh_url: []const u8,
            clone_url: []const u8,
            svn_url: []const u8,
            homepage: []const u8,
            size: i64,
            stargazers_count: i64,
            watchers_count: i64,
            language: ?u0,
            has_issues: bool,
            has_projects: bool,
            has_downloads: bool,
            has_wiki: bool,
            has_pages: bool,
            has_discussions: bool,
            forks_count: i64,
            mirror_url: ?u0,
            archived: bool,
            disabled: bool,
            open_issues_count: i64,
            license: struct {
                key: []const u8,
                name: []const u8,
                spdx_id: []const u8,
                url: []const u8,
                node_id: []const u8,
            },
            allow_forking: bool,
            is_template: bool,
            web_commit_signoff_required: bool,
            topics: []const ?u0,
            visibility: []const u8,
            forks: i64,
            open_issues: i64,
            watchers: i64,
            default_branch: []const u8,
            public: bool,
        } = null,
    },
    public: bool,
    created_at: []const u8,
    org: ?struct {
        id: i64,
        login: []const u8,
        gravatar_id: []const u8,
        url: []const u8,
        avatar_url: []const u8,
    } = null,
};
