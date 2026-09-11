// Copyright Linnet contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#ifndef LINNET_SMART_ENGLISH_FILTER_H_
#define LINNET_SMART_ENGLISH_FILTER_H_

#include <rime/filter.h>
#include <rime/dict/dictionary.h>
#include <rime/dict/user_dictionary.h>

#include <optional>
#include <string>

#include "smart_english_domain.h"
#include "smart_english_index.h"

#pragma GCC visibility push(hidden)

namespace linnet {

/// Display-order learning after OpenCC, before the final native uniquifier.
/// An eager ranker after uniquifier would bypass its published-row deduplication.
/// Uses reserved codes in the existing mode-owned Rime learning database so
/// normal clear/export/restore/sync operations include these choices.
class DisplayLearningFilter : public rime::Filter {
 public:
  explicit DisplayLearningFilter(const rime::Ticket& ticket);
  ~DisplayLearningFilter() override;
  rime::an<rime::Translation> Apply(rime::an<rime::Translation> translation,
                                   rime::CandidateList*) override;
 private:
  void OnCommit(rime::Context* context);
  rime::the<rime::UserDictionary> dictionary_;
  rime::connection commit_connection_;
};

class SmartEnglishFilter : public rime::Filter {
 public:
  explicit SmartEnglishFilter(const rime::Ticket& ticket);

  rime::an<rime::Translation> Apply(
      rime::an<rime::Translation> translation,
      rime::CandidateList*) override;
 bool AppliesToSegment(rime::Segment* segment) override;

 private:
  struct PendingSegment {
    std::string input;
    bool pinyin_flow = false;
    bool code_token = false;
    size_t start = 0;
    size_t end = 0;
  };

  const std::string schema_id_;
  const smart_english_domain::InteractionOptions options_;
  const SmartEnglishIndex index_;
  rime::an<rime::Dictionary> chinese_dictionary_;
  std::optional<PendingSegment> pending_segment_;
};

}  // namespace linnet

#pragma GCC visibility pop

#endif  // LINNET_SMART_ENGLISH_FILTER_H_
