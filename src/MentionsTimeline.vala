/*  This file is part of Cawbird, a Gtk+ linux Twitter client forked from Corebird.
 *  Copyright (C) 2013 Timm Bäder (Corebird)
 *
 *  Cawbird is free software: you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation, either version 3 of the License, or
 *  (at your option) any later version.
 *
 *  Cawbird is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License
 *  along with cawbird.  If not, see <http://www.gnu.org/licenses/>.
 */

class MentionsTimeline : Cb.MessageReceiver, DefaultTimeline {
  protected override string function {
    get {
      return "1.1/statuses/mentions_timeline.json";
    }
  }

  public MentionsTimeline(int id, Account account) {
    base (id);
    this.account = account;
    this.tweet_list.account= account;
  }

  private void stream_message_received (Cb.StreamMessageType type, Json.Node root) {
    if (type == Cb.StreamMessageType.TWEET) {
      Utils.set_rt_from_tweet (root, this.tweet_list.model, this.account);
    } else if (type == Cb.StreamMessageType.MENTION) {
      add_tweet (root);
    } else if (type == Cb.StreamMessageType.MENTIONS_LOADED) {
      this.preload_is_complete = true;
    } else if (type == Cb.StreamMessageType.DELETE) {
      int64 id = root.get_object ().get_object_member ("delete")
                     .get_object_member ("status").get_int_member ("id");
      delete_tweet (id);
    } else if (type == Cb.StreamMessageType.RT_DELETE) {
      Utils.unrt_tweet (root, this.tweet_list.model);
    } else if (type == Cb.StreamMessageType.EVENT_FAVORITE) {
      int64 id = root.get_object ().get_int_member ("id");
      toggle_favorite (id, true);
    } else if (type == Cb.StreamMessageType.EVENT_UNFAVORITE) {
      int64 id = root.get_object ().get_object_member ("target_object").get_int_member ("id");
      toggle_favorite (id, false);
    }
  }

  private void add_tweet (Json.Node root_node) {
    /* Mark tweets as seen the user has already replied to */
    var root = root_node.get_object ();
    
    if (!root.get_null_member ("retweeted_status")) {
      Utils.set_rt_from_tweet (root_node, this.tweet_list.model, this.account);
    }

    var author = root.get_object_member ("user");
    if (author.get_int_member ("id") == account.id &&
        !root.get_null_member ("in_reply_to_status_id")) {
      mark_seen (root.get_int_member ("in_reply_to_status_id"));
      return;
    }

    if (root.get_string_member ("full_text").contains ("@" + account.screen_name)) {
      GLib.DateTime now = new GLib.DateTime.now_local ();
      var t = new Cb.Tweet ();
      t.load_from_json (root_node, account.id, now);
      if (t.get_user_id () == account.id)
        return;

      if (t.retweeted_tweet != null && get_rt_flags (t) > 0)
        return;

      if (account.filter_matches (t))
        return;

      if (account.blocked_or_muted (t.get_user_id ()))
        return;

      this.balance_next_upper_change (TOP);
      if (preload_is_complete)
        t.set_seen (false);
      tweet_list.model.add (t);


      base.scroll_up (t);
      if (preload_is_complete)
        this.unread_count ++;

      if (preload_is_complete && Settings.notify_new_mentions ()) {
        string text;
        if (t.retweeted_tweet != null)
          text = Utils.unescape_html (t.retweeted_tweet.text);
        else
          text = Utils.unescape_html (t.source_tweet.text);

        /* Ignore the mention if both accounts are configured */
        if (Account.query_account_by_id (t.get_user_id ()) == null) {
          string summary = _("%s mentioned %s").printf (Utils.unescape_html (t.get_user_name ()),
                                                        account.name);
          string id = "%s-%s".printf (account.id.to_string (), "mention");
          var tuple = new GLib.Variant.tuple ({account.id, t.id});
          var notification = new GLib.Notification (summary);
          notification.set_body (text);
          notification.set_default_action_and_target_value ("app.show-window", account.id);
          notification.add_button_with_target_value ("Mark read", "app.mark-read", tuple);
          notification.add_button_with_target_value ("Reply", "app.reply-to-tweet", tuple);

          t.notification_id = id;
          GLib.Application.get_default ().send_notification (id, notification);
        }
      }
    }
  }

  public override string get_title () {
    return _("Mentions");
  }

  public override void create_radio_button (Gtk.RadioButton? group) {
    radio_button = new BadgeRadioButton (group, "cawbird-mentions-symbolic", _("Mentions"));
  }
}
