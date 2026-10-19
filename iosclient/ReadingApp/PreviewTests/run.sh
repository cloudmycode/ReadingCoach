#!/bin/sh
set -eu
repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)
test_dir=$(mktemp -d /tmp/reading-client-check.XXXXXX)
trap 'rm -rf "$test_dir"' EXIT
app="$repo_root/iosclient/ReadingApp/ReadingApp"
checks="$repo_root/iosclient/ReadingApp/PreviewTests"
swiftc -parse-as-library \
  "$app/Models/ArticleModels.swift" "$app/Models/FollowAlongResult.swift" \
  "$app/Storage/ArticleReadingHistoryStore.swift" "$checks/ArticleReadingHistoryTests.swift" \
  -o "$test_dir/reading-history-checks"
"$test_dir/reading-history-checks"
swiftc -parse-as-library \
  "$app/Models/FollowAlongResult.swift" "$checks/FollowAlongResultTests.swift" \
  -o "$test_dir/follow-along-checks"
"$test_dir/follow-along-checks"
swiftc -parse-as-library \
  "$app/Models/AudioPlaybackProgress.swift" "$checks/AudioPlaybackProgressTests.swift" \
  -o "$test_dir/audio-progress-checks"
"$test_dir/audio-progress-checks"
swiftc -parse-as-library \
  "$app/Networking/SpeechSynthesisPolicy.swift" "$checks/SpeechSynthesisPolicyTests.swift" \
  -o "$test_dir/speech-timeout-checks"
"$test_dir/speech-timeout-checks"
swiftc -parse-as-library \
  "$app/Models/ArticleModels.swift" "$app/Models/ArticleReadingLanguage.swift" \
  "$app/Models/FollowAlongResult.swift" \
  "$app/Storage/ArticleReadingHistoryStore.swift" \
  "$app/ViewModels/ArticleDetailViewModel.swift" "$checks/ArticlePlaybackTests.swift" \
  -o "$test_dir/article-playback-checks"
"$test_dir/article-playback-checks"
swiftc -parse-as-library \
  "$app/Networking/EdgeSpeechProtocol.swift" "$app/Networking/EdgeSpeechToken.swift" \
  "$app/Networking/SpeechSynthesisPolicy.swift" \
  "$app/Models/SpeechWordTiming.swift" "$checks/EdgeSpeechProtocolTests.swift" \
  -o "$test_dir/edge-speech-checks"
"$test_dir/edge-speech-checks"
swiftc -parse-as-library \
  "$app/Models/SpeechWordTiming.swift" "$checks/SpeechWordTimingTests.swift" \
  "$app/Config/AppConfig.swift" "$app/Networking/NetworkManager.swift" "$app/Networking/ReadingAPI.swift" \
  "$app/Features/ReadingChallenge/ReadingModels.swift" \
  "$app/Features/ReadingChallenge/ReadingQuizStore.swift" \
  "$app/Features/ReadingChallenge/ReadingChallengeStore.swift" \
  "$checks/ReadingClientTests.swift" -o "$test_dir/checks"
"$test_dir/checks"
swiftc -parse-as-library \
  "$app/Models/ArticleModels.swift" \
  "$app/Storage/WordBookStore.swift" "$app/Storage/ReviewTaskCache.swift" \
  "$app/ViewModels/WordBookViewModel.swift" "$app/ViewModels/ReviewTasksViewModel.swift" \
  "$checks/ListCacheTests.swift" -o "$test_dir/list-cache-checks"
"$test_dir/list-cache-checks"
