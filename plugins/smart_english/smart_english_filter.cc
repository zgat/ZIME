// Copyright Linnet contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#include "smart_english_filter.h"

#include <rime/candidate.h>
#include <rime/context.h>
#include <rime/engine.h>
#include <rime/gear/translator_commons.h>
#include <rime/language.h>
#include <rime/predict/predict_engine.h>
#include <rime/schema.h>
#include <rime/segmentation.h>
#include <rime/translation.h>

#include <algorithm>
#include <functional>
#include <limits>
#include <map>
#include <set>
#include <utility>
#include <vector>

namespace linnet {
using namespace rime;
using namespace smart_english_domain;
namespace {

// Rime dictionary weights are log(raw / 1e8). Preserve the established
// raw-weight floor without reopening the Chinese dictionary after grammar has
// adjusted the candidate's presentation weight.
constexpr double kEstablishedChinesePhraseMinimumLexicalWeight =
    -13.815510557964274;
// Abbreviations are more ambiguous than complete syllables. Requiring ten
// times the established lexical floor prevents rare accidental matches such
// as cloud -> 查漏洞 from displacing common English. Learned choices bypass it.
constexpr double kEstablishedChineseAbbreviationMinimumLexicalWeight =
    -11.512925464970229;

// Table weights use log(raw / 1e8). Only a common exact English word may
// override weak Chinese parses in Chinese mode (raw frequency >= 1 million).
// Explicit capitalization and the dedicated English mode retain their routes.
constexpr double kCommonEnglishMinimumLexicalWeight = -4.605170185988091;

bool ChineseDictionaryPhrase(const an<Phrase>& phrase) {
  return phrase && phrase->language() && phrase->language()->name() == "linnet_zh";
}

// Dictionary provenance is not a language: the combined Chinese dictionary
// also imports IBM, IME, CPU, etc. They must not inherit Chinese-intent priority.
string AsciiEntity(const string& text) {
  string result;
  bool letter = false;
  for (unsigned char byte : text) {
    if (byte >= 'A' && byte <= 'Z') byte += 'a' - 'A';
    if (byte >= 'a' && byte <= 'z') letter = true;
    else if (byte < '0' || byte > '9') return {};
    result += byte;
  }
  return letter ? result : string();
}

bool AsciiDictionaryPhrase(const an<Candidate>& candidate) {
  const auto phrase = As<Phrase>(Candidate::GetGenuineCandidate(candidate));
  return ChineseDictionaryPhrase(phrase) && !AsciiEntity(phrase->text()).empty();
}

bool HasIncompleteAsciiSyllable(const an<Candidate>& candidate,
                                const string& input,
                                const an<Dictionary>& dictionary) {
  const auto phrase = As<Phrase>(Candidate::GetGenuineCandidate(candidate));
  if (!dictionary || !ChineseDictionaryPhrase(phrase)) return false;
  bool has_non_ascii = false, has_ascii_letter = false;
  for (unsigned char c : phrase->text()) {
    has_non_ascii = has_non_ascii || c >= 0x80;
    has_ascii_letter = has_ascii_letter ||
        (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z');
  }
  // Ordinary Chinese abbreviations and standalone English completions stay
  // unchanged and need no dictionary decoding.
  if (!has_non_ascii || !has_ascii_letter) return false;
  vector<string> syllables;
  if (!dictionary->Decode(phrase->code(), &syllables)) return false;
  auto spans = phrase->spans();
  size_t start = phrase->start();
  for (const auto& syllable : syllables) {
    const size_t end = spans.NextStop(start);
    const auto entity = AsciiEntity(syllable);
    // linnet_english_entities uses uppercase canonical codes as a marker;
    // normal pinyin syllables are lowercase. Use that identity, not token
    // boundaries in the surface text (which can join adjacent entities).
    if (!entity.empty() && syllable != entity) {
      if (end <= start || end > input.size()) return true;
      const auto part = input.substr(start, end - start);
      const auto first = part.find_first_not_of(" '");
      const auto last = part.find_last_not_of(" '");
      if (first == string::npos || AsciiEntity(part.substr(first, last - first + 1)) != entity)
        return true;
    }
    start = end;
  }
  // Check native code/spans, not the surface string. This also covers a
  // previously learned mixed phrase and multi-entity/generated sentences.
  return false;
}

struct MixedTextShape {
  std::size_t entity_start = std::string::npos;
  std::size_t entity_length = 0;

  explicit operator bool() const {
    return entity_start != std::string::npos;
  }
};

MixedTextShape InspectMixedText(const string& text) {
  MixedTextShape result;
  bool has_non_ascii = false;
  for (std::size_t index = 0; index < text.size();) {
    const auto byte = static_cast<unsigned char>(text[index]);
    if (byte >= 'A' && byte <= 'Z') {
      const std::size_t start = index;
      while (index < text.size() && text[index] >= 'A' &&
             text[index] <= 'Z') {
        ++index;
      }
      const std::size_t length = index - start;
      if (result || length < 2 || length > 6) return {};
      result.entity_start = start;
      result.entity_length = length;
      continue;
    }
    if (byte < 0x80) return {};
    has_non_ascii = true;
    ++index;
  }
  return result && has_non_ascii ? result : MixedTextShape{};
}

bool IsMixedChineseCandidate(const an<Candidate>& candidate) {
  const auto phrase = As<Phrase>(candidate);
  if (!phrase || !phrase->language() ||
      phrase->language()->name() != "linnet_zh" ||
      !phrase->is_exact_match()) {
    return false;
  }
  const MixedTextShape shape = InspectMixedText(phrase->text());
  return static_cast<bool>(shape);
}

an<Candidate> ProjectSmartEnglishCandidate(
    const an<Candidate>& candidate,
    const SmartEnglishIndex& index,
    const InteractionOptions& options,
    const SpacingState& spacing,
    CaseStyle requested_case,
    bool sentence_boundary) {
  if (!candidate || candidate->type() == kMixedCandidateType) return candidate;
  const auto genuine = Candidate::GetGenuineCandidate(candidate);
  if (!genuine) return nullptr;
  if (IsMixedChineseCandidate(genuine)) {
    return New<ShadowCandidate>(genuine, kMixedCandidateType, genuine->text(),
                                genuine->comment(), false);
  }
  string text = genuine->text();
  string comment = genuine->comment();
  const bool raw = IsRawCandidate(candidate);
  if (!raw) {
    const CaseStyle case_style =
        requested_case == CaseStyle::kUnchanged &&
                options.sentence_capitalization && sentence_boundary &&
                IsSmartEnglishCandidateOrigin(candidate)
            ? CaseStyle::kCapitalized
            : requested_case;
    const bool typed_pinyin_projection =
        genuine->type() == "linnet_pinyin";
    text = ApplyCase(text, case_style, typed_pinyin_projection);
    const bool printable_english_projection =
        (typed_pinyin_projection || IsLinnetEnglishPhrase(genuine)) &&
        !text.empty();
    if (spacing.spaced &&
        !IsSuffix(NormalizeCandidate(genuine->text())) &&
        (!NormalizeCandidate(text).empty() ||
         printable_english_projection)) {
      text.insert(text.begin(), ' ');
    }
  }
  bool has_english_metadata = false;
  // Mixed-case words / lowercase acronym spellings can be native raw rows.
  // Annotate recognized alphabetic words without changing their raw identity,
  // text, order or commit path. Code tokens and unknown spelling stay raw.
  const bool raw_english_word = raw && text.size() <= 64 &&
      !LowerAsciiWord(text).empty();
  if ((!raw || raw_english_word) && !IsCustomPhrase(genuine)) {
    SmartEnglishMetadata metadata;
    if (index.LookupMetadata(MetadataKey(text), MetadataKey(genuine->text()),
                             &metadata)) {
      has_english_metadata = true;
      const string ipa = options.show_ipa ? metadata.ipa : string();
      const string translation =
          options.show_translation ? metadata.chinese_definition : string();
      comment = ipa.empty()
                    ? translation
                    : translation.empty() ? ipa : ipa + " · " + translation;
    }
  }
  const auto chinese_phrase = As<Phrase>(genuine);
  if (!raw && options.show_translation && chinese_phrase &&
      chinese_phrase->language() &&
      chinese_phrase->language()->name() == "linnet_zh") {
    const auto translations = index.LookupEnglishTranslations(genuine->text());
    if (!translations.empty()) {
      comment.assign(1, kReverseDefinitionCommentPrefix);
      for (std::size_t ordinal = 0; ordinal < translations.size(); ++ordinal) {
        if (ordinal > 0) comment.push_back(kDefinitionAlternativeSeparator);
        comment += translations[ordinal].text;
      }
    }
  }
  // English acronyms may also originate in the Chinese phrase dictionary.
  // Mark their actual metadata so the Host does not discard it as a spelling
  // hint (e.g. Chinese-mode ime -> IME).
  if ((IsSmartEnglishCandidateOrigin(candidate) ||
       (has_english_metadata && !NormalizeCandidate(MetadataKey(text), true).empty())) &&
      (options.show_ipa || options.show_translation) &&
      (comment.empty() || comment.front() != kDefinitionCommentPrefix)) {
    comment.insert(comment.begin(), kDefinitionCommentPrefix);
  }
  if (candidate == genuine && text == genuine->text() &&
      comment == genuine->comment()) {
    return genuine;
  }
  return New<ShadowCandidate>(genuine, genuine->type(), text, comment, false);
}

using CandidateProjector =
    std::function<an<Candidate>(const an<Candidate>&)>;

string DisplayChoiceCode(const string& input) {
  if (input.empty() || input.size() > 128) return string();
  string code = "zime_choice_";
  constexpr char hex[] = "0123456789abcdef";
  for (unsigned char byte : input) {
    if (byte < 0x20 || byte > 0x7e) return string();
    if (byte >= 'A' && byte <= 'Z') byte += 'a' - 'A';
    code += hex[byte >> 4];
    code += hex[byte & 15];
  }
  return code;
}

an<Candidate> DisplayCandidate(const an<Candidate>& candidate) {
  // The emoji converter tags its own output. Do not maintain a partial
  // Unicode range list that misses flags, keycaps, ZWJ or future emoji.
  if (!candidate || candidate->comment().rfind("zime-emoji:", 0) != 0) return candidate;
  const auto genuine = Candidate::GetGenuineCandidate(candidate);
  if (!genuine || genuine->text() == candidate->text()) return candidate;
  // Do not let Rime's phrase learner count selecting 😀 as selecting “笑脸”.
  // Retain only a source-headword annotation; this variant learns separately.
  auto emoji = New<SimpleCandidate>("zime_emoji", candidate->start(), candidate->end(),
      candidate->text(), string(1, '\x1b') + genuine->text(), candidate->preedit());
  emoji->set_quality(candidate->quality());
  return emoji;
}

class SmartEnglishTailTranslation : public Translation {
 public:
  SmartEnglishTailTranslation(an<Translation> translation,
                              bool drop_raw,
                              bool promote_exact,
                              CandidateProjector projector)
      : translation_(std::move(translation)),
        drop_raw_(drop_raw),
        promote_exact_(promote_exact),
        projector_(std::move(projector)) {
    Locate();
  }

  bool Next() override {
    if (exhausted()) return false;
    translation_->Next();
    return Locate();
  }

  an<Candidate> Peek() override {
    return exhausted() ? nullptr : projected_;
  }

 private:
  bool Locate() {
    projected_.reset();
    while (translation_ && !translation_->exhausted()) {
      const auto candidate = translation_->Peek();
      if (!candidate) break;
      if (!drop_raw_ ||
          !ShouldDropRawCandidate(candidate, promote_exact_)) {
        projected_ = projector_(candidate);
      }
      if (projected_) {
        set_exhausted(false);
        return true;
      }
      translation_->Next();
    }
    set_exhausted(true);
    return false;
  }

  an<Translation> translation_;
  const bool drop_raw_;
  const bool promote_exact_;
  const CandidateProjector projector_;
  an<Candidate> projected_;
};

}  // namespace

DisplayLearningFilter::DisplayLearningFilter(const Ticket& ticket) : Filter(ticket) {
  if (!engine_ || !ticket.schema) return;
  bool enabled = true;
  ticket.schema->config()->GetBool("zime_display_learning/enabled", &enabled);
  if (!enabled || !InteractionOptions::Load(ticket.schema).learning_enabled) return;
  auto component = dynamic_cast<UserDictionaryComponent*>(UserDictionary::Require("user_dictionary"));
  if (!component) return;
  dictionary_.reset(component->Create(
      ticket.schema->schema_id() == kSmartEnglishSchema ? "linnet_en" : "linnet_zh", "userdb"));
  if (!dictionary_ || !dictionary_->Load()) { dictionary_.reset(); return; }
  commit_connection_ = engine_->context()->commit_notifier().connect(
      [this](Context* context) { OnCommit(context); });
}

DisplayLearningFilter::~DisplayLearningFilter() { commit_connection_.disconnect(); }

void DisplayLearningFilter::OnCommit(Context* context) {
  if (!dictionary_ || !context) return;
  for (const auto& segment : context->composition()) {
    const auto candidate = segment.GetSelectedCandidate();
    if (!candidate || segment.status < Segment::kSelected ||
        IsRawCandidate(candidate) || IsCustomPhrase(Candidate::GetGenuineCandidate(candidate)) ||
        candidate->end() <= candidate->start() || candidate->end() > context->input().size()) continue;
    const auto code = DisplayChoiceCode(context->input().substr(
        candidate->start(), candidate->end() - candidate->start()));
    if (code.empty()) continue;
    // Lookup refreshes the shared userdb tick before this writer updates it.
    UserDictEntryIterator existing;
    dictionary_->LookupWords(&existing, code, false);
    DictEntry entry;
    entry.custom_code = code + " ";
    entry.text = candidate->text();
    dictionary_->UpdateEntry(entry, 1);
  }
}

an<Translation> DisplayLearningFilter::Apply(an<Translation> translation, CandidateList*) {
  if (!translation) return New<FifoTranslation>();
  if (!dictionary_ && (translation->exhausted() ||
      !HasCandidateType(translation->Peek(), kLiteralMixedCandidateType)))
    return New<SmartEnglishTailTranslation>(translation, false, false, DisplayCandidate);
  auto result = New<FifoTranslation>();
  struct Row { an<Candidate> candidate; int count = 0; };
  std::vector<Row> rows;
  bool has_emoji = false;
  bool has_english_alternative = false;
  bool has_literal_mixed = false;
  const auto& input = engine_->context()->input();
  for (size_t index = 0; index < kCandidateLimit && !translation->exhausted(); ++index) {
    auto candidate = DisplayCandidate(translation->Peek());
    if (!candidate) break;
    has_emoji = has_emoji || candidate->type() == "zime_emoji";
    has_literal_mixed = has_literal_mixed || HasCandidateType(candidate, kLiteralMixedCandidateType);
    has_english_alternative = has_english_alternative ||
        ((AsciiDictionaryPhrase(candidate) || IsLinnetEnglishPhrase(Candidate::GetGenuineCandidate(candidate))) &&
         candidate->end() <= input.size() &&
         candidate->end() > candidate->start() &&
         AsciiEntity(candidate->text()) != AsciiEntity(input.substr(
             candidate->start(), candidate->end() - candidate->start())));
    const auto phrase = As<Phrase>(Candidate::GetGenuineCandidate(candidate));
    rows.push_back({candidate, phrase ? std::max(0, phrase->entry().commit_count) : 0});
    translation->Next();
  }
  if (dictionary_ && (has_emoji || has_english_alternative || has_literal_mixed)) {
    std::map<string, std::map<string, int>> counts;
    for (auto& row : rows) {
      const auto& candidate = row.candidate;
      if (candidate->end() > input.size() || candidate->end() <= candidate->start()) continue;
      const auto code = DisplayChoiceCode(input.substr(candidate->start(), candidate->end() - candidate->start()));
      if (code.empty()) continue;
      auto found = counts.find(code);
      if (found == counts.end()) {
        std::map<string, int> values;
        UserDictEntryIterator entries;
        dictionary_->LookupWords(&entries, code, false);
        for (; !entries.exhausted(); entries.Next()) {
          if (const auto entry = entries.Peek()) values[entry->text] = std::max(0, entry->commit_count);
        }
        found = counts.emplace(code, std::move(values)).first;
      }
      const int choice_count = found->second[candidate->text()];
      // Native English counts belong to the canonical code, not this prefix
      // or transposed alias. Only a choice for this input may override the
      // exact-match baseline (i -> IME, nui -> niu), regardless of emoji.
      row.count = has_english_alternative && !AsciiEntity(candidate->text()).empty()
          ? choice_count : std::max(row.count, choice_count);
    }
    // Keep custom phrases, literal input and partial-match boundaries intact.
    for (auto begin = rows.begin(); begin != rows.end();) {
      const auto eligible = [](const Row& row) {
        return !IsRawCandidate(row.candidate) &&
          !IsCustomPhrase(Candidate::GetGenuineCandidate(row.candidate));
      };
      if (!eligible(*begin)) { ++begin; continue; }
      auto end = std::next(begin);
      while (end != rows.end() && eligible(*end) &&
             end->candidate->start() == begin->candidate->start() &&
             end->candidate->end() == begin->candidate->end()) ++end;
      std::stable_sort(begin, end, [](const Row& left, const Row& right) { return left.count > right.count; });
      begin = end;
    }
  }
  if (has_literal_mixed) {
    // Page size controls presentation, not which literal choices can learn.
    // Rank the same bounded pool first, then keep one native partial choice
    // on the first page; all remaining mixed alternatives stay reachable.
    const auto partial = std::find_if(rows.begin(), rows.end(), [&](const Row& row) {
      return row.candidate->start() == rows.front().candidate->start() &&
          row.candidate->end() < rows.front().candidate->end() && !IsRawCandidate(row.candidate);
    });
    const auto first_page_mixed = std::clamp(engine_->schema()->page_size() - 1, 1, 8);
    if (partial != rows.end() && std::distance(rows.begin(), partial) > first_page_mixed)
      std::rotate(rows.begin() + first_page_mixed, partial, std::next(partial));
  }
  for (const auto& row : rows) result->Append(row.candidate);
  return result + New<SmartEnglishTailTranslation>(translation, false, false, DisplayCandidate);
}

SmartEnglishFilter::SmartEnglishFilter(const Ticket& ticket)
    : Filter(ticket),
      schema_id_(ticket.schema ? ticket.schema->schema_id() : string()),
      options_(InteractionOptions::Load(ticket.schema)),
      index_(PredictEngineComponent::Shared()->GetInstance(ticket)) {
  if (engine_ && schema_id_ != kSmartEnglishSchema) {
    if (auto component = Dictionary::Require("dictionary")) {
      chinese_dictionary_.reset(component->Create(Ticket(engine_, "translator")));
      if (chinese_dictionary_ && !chinese_dictionary_->Load()) chinese_dictionary_.reset();
    }
  }
}

an<Translation> SmartEnglishFilter::Apply(an<Translation> translation,
                                           CandidateList*) {
  auto result = New<FifoTranslation>();
  if (!translation || !engine_) return result;

  Context* context = engine_->context();
  // One lazy admission boundary covers both the ranked prefix and all later
  // pages. Reject wo+i -> 我IME before it can displace the safe partial 我;
  // keep wo+ime -> 我IME and every ordinary Chinese abbreviation.
  translation = New<SmartEnglishTailTranslation>(translation, false, false,
      [dictionary = chinese_dictionary_, input = context->input()](const an<Candidate>& candidate) {
        return HasIncompleteAsciiSyllable(candidate, input, dictionary) ? nullptr : candidate;
      });
  const auto pending_segment =
      std::exchange(pending_segment_, std::nullopt);
  const string ranking_input =
      pending_segment ? pending_segment->input : string();
  const bool is_pinyin_flow = pending_segment && pending_segment->pinyin_flow;
  const bool is_code_token = pending_segment && pending_segment->code_token;
  string input_word = LowerAsciiWord(ranking_input);
  struct RankedCandidate {
    an<Candidate> candidate, genuine;
    string word;
    std::size_t original = 0;
    std::size_t static_rank = std::numeric_limits<std::size_t>::max();
    std::uint16_t session_count = 0;
    int commit_count = 0;
    bool raw = false, exact = false, ambiguous_english = false,
         chinese = false, mixed = false, ascii_dictionary = false,
         strong_chinese_collision = false;
  };
  std::vector<RankedCandidate> candidates;
  candidates.reserve(kCandidateLimit);
  for (std::size_t index = 0;
       index < kCandidateLimit && !translation->exhausted(); ++index) {
    auto candidate = translation->Peek();
    if (!candidate) break;
    auto genuine = Candidate::GetGenuineCandidate(candidate);
    const string candidate_text = genuine ? genuine->text() : string();
    candidates.push_back(
        {candidate, genuine, NormalizeCandidate(candidate_text), index});
    translation->Next();
  }

  const auto context_tokens =
      ParseContext(context->get_property(rime::predict::kContextProperty));
  const string previous =
      context_tokens.empty() ? string() : context_tokens.back();
  const auto bigrams = options_.learning_enabled
                           ? SessionBigrams::Load(
                                 context->get_property(kBigramProperty))
                           : SessionBigrams{};
  const auto static_ranks = index_.LookupStaticOrdinals(
      context->get_property(rime::predict::kStaticKeyProperty));
  bool has_exact = false, has_ambiguous_english = false,
       has_pinyin = false, has_mixed = false;
  for (auto& item : candidates) {
    if (!item.genuine) continue;
    item.raw = IsRawCandidate(item.candidate);
    has_pinyin = has_pinyin || item.genuine->type() == "linnet_pinyin";
    const auto phrase = rime::As<Phrase>(item.genuine);
    item.commit_count = phrase ? std::max(0, phrase->entry().commit_count) : 0;
    item.mixed = IsMixedChineseCandidate(item.genuine);
    item.ascii_dictionary = AsciiDictionaryPhrase(item.genuine);
    item.chinese = !item.mixed && !item.ascii_dictionary && ChineseDictionaryPhrase(phrase);
    item.exact = !input_word.empty() && item.word == input_word &&
                 (IsLinnetEnglishPhrase(item.genuine) || item.ascii_dictionary) &&
                 (!phrase || phrase->is_exact_match()) &&
                 item.candidate->type() != "linnet_correction";
    // A table phrase whose spelling differs from the live segment reached us
    // through a derived spelling or completion key, not direct English input.
    item.ambiguous_english = !input_word.empty() && item.word != input_word &&
                             (IsLinnetEnglishPhrase(item.genuine) || item.ascii_dictionary);
    has_exact = has_exact || item.exact;
    has_ambiguous_english = has_ambiguous_english || item.ambiguous_english;
    has_mixed = has_mixed || item.mixed;
    item.session_count = previous.empty() || item.word.empty()
                             ? 0
                             : bigrams.Count(previous, item.word);
    const auto static_rank = static_ranks.find(item.word);
    if (static_rank != static_ranks.end()) {
      item.static_rank = static_rank->second;
    }
  }
  // Exact English spelling precedes its derived aliases in the cold-start
  // order. Stay inside same-span English runs: do not cross Chinese, custom
  // or partial choices. The display learner can still override this baseline
  // when the user explicitly chooses an alias for this particular input.
  for (auto begin = candidates.begin(); begin != candidates.end();) {
    const auto english = [](const auto& item) { return item.exact || item.ambiguous_english; };
    if (!english(*begin)) { ++begin; continue; }
    auto end = std::next(begin);
    while (end != candidates.end() && english(*end) &&
           end->genuine->start() == begin->genuine->start() &&
           end->genuine->end() == begin->genuine->end()) ++end;
    std::stable_partition(begin, end, [](const auto& item) { return item.exact; });
    begin = end;
  }
  // Chinese mode owns lowercase intent. A common English word can lead only
  // when there is no established or learned Chinese word for the same span.
  const bool explicit_english_case = !input_word.empty() && ranking_input != input_word;
  const bool lowercase_chinese_input =
      (has_exact || has_ambiguous_english || has_mixed) &&
      schema_id_ != kSmartEnglishSchema &&
      !explicit_english_case;
  const bool lowercase_chinese_exact = has_exact && lowercase_chinese_input;
  auto bilingual_candidate = std::find_if(candidates.begin(), candidates.end(),
      [](const auto& item) { return item.exact; });
  if (bilingual_candidate == candidates.end()) {
    bilingual_candidate = std::find_if(
        candidates.begin(), candidates.end(), [](const auto& item) {
          return item.ambiguous_english;
        });
  }
  if (bilingual_candidate == candidates.end()) {
    bilingual_candidate = std::find_if(candidates.begin(), candidates.end(),
        [](const auto& item) { return item.mixed; });
  }
  bool has_same_span_chinese = false;
  bool has_strong_same_span_chinese = false;
  const bool common_exact_english = std::any_of(
      candidates.begin(), candidates.end(), [](const auto& item) {
        const auto phrase = item.exact ? rime::As<Phrase>(item.genuine) : nullptr;
        return phrase && phrase->weight() >= kCommonEnglishMinimumLexicalWeight;
      });
  if (lowercase_chinese_input && bilingual_candidate != candidates.end()) {
    for (auto& item : candidates) {
      if (!item.chinese ||
          item.genuine->start() != bilingual_candidate->genuine->start() ||
          item.genuine->end() != bilingual_candidate->genuine->end()) {
        continue;
      }
      has_same_span_chinese = true;
      const auto phrase = rime::As<Phrase>(item.genuine);
      const auto system_weight =
          phrase ? phrase->system_lexical_weight() : std::nullopt;
      // Abbreviations such as ke+y -> 可以 are valid Chinese intent. Native
      // user_phrase identity must win even for low-frequency words; consulting
      // only the system weight would hide learning behind a fixed English row.
      item.strong_chinese_collision = phrase && phrase->is_exact_match() &&
          (item.genuine->type() == "user_phrase" ||
           (phrase->spelling_type() <= kAbbreviation && system_weight &&
            *system_weight >= (phrase->spelling_type() == kAbbreviation
              ? kEstablishedChineseAbbreviationMinimumLexicalWeight
              : kEstablishedChinesePhraseMinimumLexicalWeight)));
      has_strong_same_span_chinese = has_strong_same_span_chinese ||
          item.strong_chinese_collision;
    }
  }
  const bool single_letter_chinese_input =
      lowercase_chinese_exact && input_word.size() == 1 &&
      has_same_span_chinese;
  const bool preserve_chinese_exact =
      lowercase_chinese_exact &&
      (single_letter_chinese_input || has_strong_same_span_chinese ||
       (has_same_span_chinese && !common_exact_english));
  const bool preserve_chinese_ambiguous =
      has_ambiguous_english && lowercase_chinese_input &&
      has_same_span_chinese;
  const bool promote_exact = has_exact && !preserve_chinese_exact;
  const bool promote_mixed =
      !has_exact && has_mixed && !has_same_span_chinese;
  const bool has_non_raw = std::any_of(
      candidates.begin(), candidates.end(),
      [](const auto& item) { return item.genuine && !item.raw; });
  const auto move_same_span_chinese_first =
      [&](auto english, const auto& eligible_chinese) {
        if (english == candidates.end()) return;
        const auto chinese = std::find_if(
            english, candidates.end(), [&](const auto& item) {
              return item.chinese && eligible_chinese(item) &&
                     item.genuine->start() == english->genuine->start() &&
                     item.genuine->end() == english->genuine->end();
            });
        if (chinese != candidates.end() && english < chinese) {
          std::rotate(english, chinese, std::next(chinese));
        }
      };
  // Prefetching must not promote Rime's echo fallback. A real exact English
  // row also retires the typed typo fallback.
  if (has_non_raw && (!is_code_token || has_mixed)) {
    candidates.erase(
        std::remove_if(candidates.begin(), candidates.end(),
                       [promote_exact](const auto& item) {
                         return ShouldDropRawCandidate(item.candidate,
                                                       promote_exact);
                       }),
        candidates.end());
  }
  if (!is_pinyin_flow && has_mixed && has_same_span_chinese) {
    const auto mixed = std::find_if(candidates.begin(), candidates.end(),
                                    [](const auto& item) {
                                      return item.mixed;
                                    });
    move_same_span_chinese_first(mixed,
                                 [](const auto&) { return true; });
  }
  if (!is_pinyin_flow && (has_exact || promote_mixed)) {
    std::stable_partition(candidates.begin(), candidates.end(), [has_exact](const auto& item) {
      return has_exact ? !item.mixed : item.mixed;
    });
  }
  if (!is_pinyin_flow && has_exact) {
    if (promote_exact && schema_id_ == kSmartEnglishSchema) {
      std::stable_sort(candidates.begin(), candidates.end(),
                       [](const auto& left, const auto& right) {
        const auto left_group = left.raw ? 0 : left.exact ? 1 : 2;
        const auto right_group = right.raw ? 0 : right.exact ? 1 : 2;
        if (left_group != right_group) return left_group < right_group;
        if (left_group != 2) return left.original < right.original;
        const bool left_session = left.session_count > 0;
        const bool right_session = right.session_count > 0;
        if (left_session != right_session) return left_session;
        if (left.session_count != right.session_count) {
          return left.session_count > right.session_count;
        }
        const bool left_static =
            left.static_rank != std::numeric_limits<std::size_t>::max();
        const bool right_static =
            right.static_rank != std::numeric_limits<std::size_t>::max();
        if (left_static != right_static) return left_static;
        if (left.static_rank != right.static_rank) {
          return left.static_rank < right.static_rank;
        }
        return left.original < right.original;
      });
    } else if (promote_exact) {
      const auto exact = std::find_if(
          candidates.begin(), candidates.end(),
          [](const auto& item) { return item.exact; });
      if (exact != candidates.end()) {
        auto insertion = exact;
        while (insertion != candidates.begin()) {
          const auto previous_candidate = std::prev(insertion);
          if ((!previous_candidate->chinese && !previous_candidate->ascii_dictionary) ||
              previous_candidate->genuine->start() !=
                  exact->genuine->start() ||
              previous_candidate->genuine->end() != exact->genuine->end()) {
            break;
          }
          insertion = previous_candidate;
        }
        std::rotate(insertion, exact, std::next(exact));
      }
    } else if (preserve_chinese_exact) {
      const auto exact = std::find_if(
          candidates.begin(), candidates.end(),
          [](const auto& item) { return item.exact; });
      move_same_span_chinese_first(exact, [&](const auto& item) {
        return single_letter_chinese_input || !common_exact_english ||
               item.strong_chinese_collision;
      });
    }
  }
  if (!is_pinyin_flow && preserve_chinese_ambiguous) {
    const auto ambiguous_english = std::find_if(
        candidates.begin(), candidates.end(), [](const auto& item) {
          return item.ambiguous_english;
        });
    move_same_span_chinese_first(ambiguous_english,
                                 [](const auto&) { return true; });
  }

  // Language priority is a cold-start policy, not a permanent position. Rime
  // exposes durable selection counts for both user_phrase and user_table.
  // Their quality/weight values use different formulas and user-dictionary
  // totals, so comparing those values across languages would be misleading.
  // Move only the learned exact English row within its same-span Chinese
  // block. Preserve native Chinese order and custom/partial-match barriers;
  // equally or more frequently selected Chinese rows keep priority on ties.
  if (!is_pinyin_flow && lowercase_chinese_exact && options_.learning_enabled) {
    const auto exact = std::find_if(candidates.begin(), candidates.end(),
        [](const auto& item) { return item.exact && item.commit_count > 0; });
    if (exact != candidates.end()) {
      const auto same_span_chinese = [&](const auto& item) {
        return item.chinese && item.genuine->start() == exact->genuine->start() &&
               item.genuine->end() == exact->genuine->end();
      };
      auto begin = exact;
      while (begin != candidates.begin() && same_span_chinese(*std::prev(begin))) --begin;
      auto end = std::next(exact);
      while (end != candidates.end() && same_span_chinese(*end)) ++end;
      auto insertion = begin;
      for (auto row = begin; row != end; ++row) {
        if (row != exact && row->commit_count >= exact->commit_count) {
          insertion = std::next(row);
        }
      }
      if (insertion < exact) {
        std::rotate(insertion, exact, std::next(exact));
      } else if (insertion > exact) {
        std::rotate(exact, std::next(exact), insertion);
      }
    }
  }

  // Hallelujah appends pinyin-to-English results after ordinary English
  // completion/correction. Keep that order even when Rime merges translator
  // streams by quality. The explicit Chinese lookup remains an already
  // ordered, tagged flow and never enters this branch.
  if (schema_id_ == "linnet_en" && has_pinyin) {
    std::stable_partition(candidates.begin(), candidates.end(),
                          [](const auto& item) {
                            return !item.genuine ||
                                   item.genuine->type() != "linnet_pinyin";
                          });
  }

  const auto spacing =
      SpacingState::Load(context->get_property(kSpacingProperty));
  const CaseStyle requested_case = RequestedCase(ranking_input);
  const bool sentence_boundary = SentenceBoundaryObserved(context);
  const CandidateProjector projector =
      [index = index_, options = options_, spacing, requested_case,
       sentence_boundary](const an<Candidate>& candidate) {
        return ProjectSmartEnglishCandidate(candidate, index, options, spacing,
                                            requested_case,
                                            sentence_boundary);
      };
  // A partial Chinese match is not a whole-input candidate. When there is no
  // credible full-span result, retain the unmatched spelling literally instead
  // of inventing an English completion or requiring a second selection.
  // Native full Chinese/mixed/custom results still bypass the fallback.
  // English must also be credible when a complete Chinese prefix exists.
  const bool has_complete_chinese_prefix = pending_segment && std::any_of(
      candidates.begin(), candidates.end(), [&](const auto& item) {
        const auto phrase = As<Phrase>(item.genuine);
        return item.chinese && phrase && phrase->is_exact_match() &&
            phrase->spelling_type() <= kFuzzySpelling &&
            phrase->start() == pending_segment->start &&
            phrase->end() >= phrase->start() + 2 && phrase->end() < pending_segment->end;
      });
  if (pending_segment && schema_id_ != kSmartEnglishSchema &&
      !is_pinyin_flow && !is_code_token && !explicit_english_case &&
      std::none_of(candidates.begin(), candidates.end(), [&](const auto& item) {
        if (item.raw || item.candidate->start() != pending_segment->start ||
            item.candidate->end() != pending_segment->end) return false;
        // Rare ASCII dictionary hits and derived aliases must not prevent a
        // complete Chinese syllable + literal suffix from being offered.
        // Keep common exact English, native Chinese/mixed and custom routes.
        return !has_complete_chinese_prefix || !(item.exact || item.ambiguous_english) ||
            (item.exact && common_exact_english);
      })) {
    const auto is_prefix = [&](const auto& item) {
      const auto phrase = As<Phrase>(item.genuine);
      return ChineseDictionaryPhrase(phrase) && phrase->is_exact_match() &&
          phrase->start() == pending_segment->start &&
          phrase->end() > phrase->start() && phrase->end() < pending_segment->end &&
          std::any_of(phrase->text().begin(), phrase->text().end(),
                      [](unsigned char byte) { return byte >= 0x80; });
    };
    size_t prefix_end = pending_segment->start;
    for (const auto& item : candidates) {
      if (is_prefix(item)) prefix_end = std::max(prefix_end, item.genuine->end());
    }
    const auto suffix = pending_segment->input.substr(prefix_end - pending_segment->start);
    const bool literal_letters = !suffix.empty() &&
        std::all_of(suffix.begin(), suffix.end(), [](unsigned char byte) {
          return (byte >= 'a' && byte <= 'z') || (byte >= 'A' && byte <= 'Z');
        });
    if (prefix_end > pending_segment->start && literal_letters) {
      // Keep the learning pool independent of page size. The display filter
      // reserves a first-page native partial slot after ranking this pool.
      // Never drain the lazy tail or materialize thousands of prefixes.
      constexpr size_t limit = 8;
      std::set<string> emitted;
      for (const auto& item : candidates) {
        if (!is_prefix(item) || item.genuine->end() != prefix_end) continue;
        const string text = item.genuine->text() + suffix;
        if (!emitted.insert(text).second) continue;
        // This is not a dictionary Phrase or a shadow of the shorter prefix:
        // its text AND consumed range include the raw suffix. Display-choice
        // learning owns it, so a selection never teaches wo -> 我v to Rime.
        auto literal = New<SimpleCandidate>(kLiteralMixedCandidateType,
            pending_segment->start, pending_segment->end, text, string(),
            pending_segment->input);
        literal->set_quality(item.candidate->quality());
        result->Append(literal);
        if (emitted.size() >= limit) break;
      }
    }
  }
  for (auto& item : candidates) {
    if (const auto projected = projector(item.candidate)) {
      result->Append(projected);
    }
  }
  // Only the bounded prefix is re-ranked. The same lazy projection remains
  // authoritative for the unbounded tail, so Chinese candidate 65+ stays
  // reachable without bypassing spacing, case or metadata.
  an<Translation> ranked_prefix = result;
  an<Translation> tail = New<SmartEnglishTailTranslation>(
      translation, has_non_raw, promote_exact, projector);
  return ranked_prefix + tail;
}

bool SmartEnglishFilter::AppliesToSegment(Segment* segment) {
  pending_segment_.reset();
  if (!segment || segment->HasTag("text_expander")) {
    return false;
  }
  // A code-shaped segment can still contain the one native mixed sentence
  // produced from an explicit Shift entity with parseable Chinese on both
  // sides. Let the existing candidate classifier see that sentence; ordinary
  // URLs and identifiers have no such native candidate and retain their raw
  // route unchanged.
  const bool applies =
      segment->HasTag("linnet_pinyin") || segment->HasTag("abc") ||
      (schema_id_ == "linnet_en" &&
       (segment->HasTag("zz_english") || segment->HasTag("prediction")));
  if (!applies || !engine_ || !engine_->context()) return false;

  // ConcreteEngine translates this exact Segment and immediately invokes
  // Apply after this predicate. Capture the same range once; composition.back
  // may name a later segment, while Context::input still includes confirmed
  // prefixes and therefore is not a ranking input.
  const string& composition_input = engine_->context()->composition().input();
  if (segment->start > segment->end ||
      segment->end > composition_input.size()) {
    return false;
  }
  pending_segment_ = PendingSegment{
      composition_input.substr(segment->start,
                               segment->end - segment->start),
      segment->HasTag("linnet_pinyin"),
      segment->HasTag("zz_code_token"),
      segment->start, segment->end};
  return true;
}

}  // namespace linnet
