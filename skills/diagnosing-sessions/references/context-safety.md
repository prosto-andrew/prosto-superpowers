# Context safety for session transcripts

One transcript record can exceed a megabyte or embed a whole history. Printing
one whole record can overflow the context of the session doing the diagnosis.
Every reader of a session file, controller or subagent, follows these rules for
every file, every time.

1. **Measure before reading.**

   ```bash
   wc -lc "$F"
   awk '{ if (length($0) > 100000) print NR, length($0) }' "$F"   # long lines
   ```

2. **Never `cat` or `grep` for content.** Get line numbers and counts
   first (`grep -n … | cut -d: -f1`, `jq -r '.type' | sort | uniq -c`),
   then small fields from specific lines (`sed -n Np | jq -c '{…}'` or
   `| cut -c1-500`). Use the field-extraction commands established during
   discovery for the source in front of you.

   Without `jq`, the same two moves in Python (`python` on Windows,
   `python3` elsewhere):

   ```bash
   # census of record types
   python -c 'import json,sys,collections; print(collections.Counter(json.loads(l).get("type") for l in open(sys.argv[1],encoding="utf-8")))' "$F"

   # one trimmed field from line N
   python -c 'import json,sys,itertools; l=next(itertools.islice(open(sys.argv[1],encoding="utf-8"),int(sys.argv[2])-1,None)); o=json.loads(l); print(o.get("type"), o.get("timestamp"), str(o.get("message"))[:500])' "$F" N
   ```

3. **Narrow anything over 500 characters.** If a command returns more than
   500 characters for one record, tighten the field or the slice.
4. **Read-only.** Never modify, move, or delete a session file.
5. **Nothing leaves the machine.** Extracted text goes into your own context
   and the workspace only — never into a network tool, a web search, or a
   message to anyone.
