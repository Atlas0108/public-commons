enum PostKind {
  helpOffer,
  helpRequest,
  /// Community gathering; stored in the `posts` collection with event fields.
  communityEvent,
  /// Short text / image update for a [CommonsPost.groupId] group feed.
  bulletin,
}

String postKindToFirestore(PostKind k) {
  switch (k) {
    case PostKind.helpOffer:
      return 'help_offer';
    case PostKind.helpRequest:
      return 'help_request';
    case PostKind.communityEvent:
      return 'community_event';
    case PostKind.bulletin:
      return 'bulletin';
  }
}

PostKind? postKindFromFirestore(String? v) {
  switch (v) {
    case 'help_offer':
      return PostKind.helpOffer;
    case 'help_request':
      return PostKind.helpRequest;
    case 'community_event':
      return PostKind.communityEvent;
    case 'bulletin':
      return PostKind.bulletin;
    default:
      return null;
  }
}
