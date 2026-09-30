-- Cite the notes an answer was grounded in.
--
-- Notesy now returns the lecture documents it retrieved alongside the answer,
-- and the chat screen renders them as "from: <note>" chips. Without a place to
-- store them, a citation would appear for one turn and then vanish the moment
-- the conversation was reopened - which reads as a bug, and defeats the point
-- of showing provenance in the first place.
--
-- Nullable on purpose: assistant replies with no retrieved material (and every
-- user message) simply carries NULL.

alter table public.ai_messages
  add column if not exists sources text[];

comment on column public.ai_messages.sources is
  'Distinct note titles (with page, e.g. "Week 3 (p.4)") the assistant answer was grounded in. Empty/null when nothing was retrieved.';

-- Existing rows are historical and have no recorded provenance.
-- No backfill: guessing a source would be worse than showing none.
