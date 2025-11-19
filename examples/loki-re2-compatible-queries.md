# Loki RE2-Compatible Query Guide

Loki uses Go's RE2 regex engine, which has some limitations compared to other regex flavors (PCRE, Perl, etc.). This guide provides RE2-compatible alternatives for common query patterns.

## Common RE2 Limitations

### ❌ NOT Supported in RE2
- Named capture groups: `(?P<name>...)` or `(?<name>...)`
- Lookahead assertions: `(?=...)`, `(?!...)`
- Lookbehind assertions: `(?<=...)`, `(?<!...)`
- Backreferences: `\1`, `\2`, etc.
- Conditional expressions: `(?(condition)yes|no)`
- Complex nested quantifiers: `(a+)+`, `(a*)*`

### ✅ Supported in RE2
- Case-insensitive flag: `(?i)`
- Non-capturing groups: `(?:...)`
- Character classes: `[a-z]`, `[^0-9]`, `\d`, `\w`, `\s`
- Quantifiers: `*`, `+`, `?`, `{n}`, `{n,}`, `{n,m}`
- Non-greedy quantifiers: `*?`, `+?`, `??`
- Alternation: `|`
- Anchors: `^`, `$`, `\b`

## Fixed Queries

### Error Detection

**❌ BROKEN (Original)**:
```logql
{job="jenkins-job-logs"} |~ "(?i)(error|exception|failed).*?(\w+Error|\w+Exception)"
```
**Error**: `Invalid regular expression: Invalid group`

**✅ FIXED (RE2-Compatible)**:
```logql
# Simple error detection
{job="jenkins-job-logs"} |~ "(?i)(error|exception|failed)"

# Match specific error types (without complex capture groups)
{job="jenkins-job-logs"} |~ "(?i)(IOException|NullPointerException|RuntimeException|SQLException)"

# Match lines containing "Error" or "Exception" (word boundary)
{job="jenkins-job-logs"} |~ "(?i)(\\bError\\b|\\bException\\b)"

# Match error patterns with context (simplified)
{job="jenkins-job-logs"} |~ "(?i)(error|exception)" | line_format "{{.}}"
```

### Build Failure Detection

**❌ BROKEN**:
```logql
{job="jenkins-job-logs"} |~ "(?i)build.*?(failed|error).*?(\w+Error)"
```

**✅ FIXED**:
```logql
# Detect build failures
{job="jenkins-job-logs"} |~ "(?i)(build.*(failed|error)|error.*build)"

# Specific build failure messages
{job="jenkins-job-logs"} |~ "(?i)(BUILD FAILED|BUILD ERROR|compilation failed)"

# Build failures with team filter
{job="jenkins-job-logs", team="devops"} |~ "(?i)(build.*(failed|error))"
```

### Stack Trace Detection

**❌ BROKEN**:
```logql
{job="jenkins"} |~ "(?i).*Exception.*\n\s+at.*"
```
**Issue**: Multi-line patterns don't work as expected

**✅ FIXED**:
```logql
# Single-line exception detection
{job="jenkins"} |~ "(?i)(Exception|Error): "

# Stack trace lines (starts with "at ")
{job="jenkins"} |~ "^\\s+at \\w+\\.\\w+"

# Combined with filter
{job="jenkins"} |~ "(?i)Exception" | line_format "{{.}}"
```

### Container Error Detection

**❌ BROKEN**:
```logql
{job="jenkins"} |~ "(?i)(docker|container).*(?:error|fail|exit.*[^0])"
```

**✅ FIXED**:
```logql
# Docker/container errors
{job="jenkins"} |~ "(?i)(docker|container).*(error|fail|exited)"

# Container exit codes (non-zero)
{job="jenkins"} |~ "(?i)exit code [1-9]"

# Combined container issues
{job="jenkins"} |~ "(?i)((docker|container).*(error|fail)|exit code [1-9])"
```

## Grafana Dashboard Query Examples

### 1. Error Rate Over Time

```logql
# Count errors per minute
sum(rate(count_over_time({job="jenkins-job-logs"} |~ "(?i)(error|exception|failed)" [1m])[5m:])) by (team)

# Error percentage
(
  sum(rate(count_over_time({job="jenkins-job-logs"} |~ "(?i)(error|exception)" [1m])[5m:])) by (team)
  /
  sum(rate(count_over_time({job="jenkins-job-logs"} [1m])[5m:])) by (team)
) * 100
```

### 2. Top Error Types

```logql
# Most common errors
topk(10, sum(count_over_time({job="jenkins-job-logs"} |~ "(?i)(error|exception)" [24h])) by (job_name))

# Build failures by team
topk(5, sum(count_over_time({job="jenkins-job-logs"} |~ "(?i)(BUILD FAILED|FAILURE)" [24h])) by (team))
```

### 3. Log Filtering with Multiple Conditions

```logql
# Errors in specific job
{job="jenkins-job-logs", job_name="my-pipeline"} |~ "(?i)(error|exception)"

# Exclude known non-critical errors
{job="jenkins-job-logs"} |~ "(?i)(error|exception)" != "(?i)(warning|info)"

# Errors with specific keywords
{job="jenkins-job-logs"} |~ "(?i)error" |~ "(?i)(timeout|connection|network)"
```

### 4. Build Duration Analysis

```logql
# Builds taking longer than 1 hour
{job="jenkins-job-logs"} |~ "Duration: [1-9][0-9]* hr"

# Quick builds (under 5 minutes)
{job="jenkins-job-logs"} |~ "Duration: [0-4] min"
```

### 5. Security-Related Logs

```logql
# Authentication failures
{job="jenkins"} |~ "(?i)(authentication|auth).*(fail|denied|reject)"

# Permission issues
{job="jenkins"} |~ "(?i)(permission|access).*(denied|forbidden|unauthorized)"
```

## LogQL Best Practices for RE2

### 1. Keep Patterns Simple
```logql
# ✅ Good - simple alternation
|~ "(error|exception|failed)"

# ❌ Bad - complex nested groups
|~ "(?i)(error|exception|failed).*?(\w+Error|\w+Exception)"
```

### 2. Use Character Classes Instead of Complex Patterns
```logql
# ✅ Good - character class
|~ "[0-9]{3} (Error|Exception)"

# ❌ Bad - complex pattern
|~ "(?:error|fail).*?[A-Z][a-z]+Error"
```

### 3. Filter Early, Parse Later
```logql
# ✅ Good - filter first, then extract
{job="jenkins"} |~ "(?i)error" | json | line_format "{{.message}}"

# ❌ Bad - trying to do everything in one regex
{job="jenkins"} |~ "(?i)error.*?(?:message|msg):\\s*(.+)"
```

### 4. Use Multiple Filters Instead of Complex OR
```logql
# ✅ Good - multiple simple filters
{job="jenkins"} |~ "(?i)error" |~ "(?i)(timeout|network)"

# ❌ Bad - complex single regex
{job="jenkins"} |~ "(?i)(?:error.*timeout|timeout.*error|network.*error)"
```

### 5. Leverage Label Filters
```logql
# ✅ Good - use labels first
{job="jenkins", team="devops"} |~ "(?i)error"

# ❌ Bad - trying to extract everything from log line
{job="jenkins"} |~ "(?i)team=devops.*error"
```

## Testing Your Queries

### 1. Use Grafana Explore
- Go to: `http://monitoring-vm:9300/explore`
- Select Loki datasource
- Test your regex patterns interactively

### 2. Verify Regex Online
- Use RE2 tester: https://regex101.com/ (select "Golang" flavor)
- Test patterns before using in Grafana

### 3. Check Loki Logs for Errors
```bash
# View Loki logs for regex errors
docker logs loki-production | grep -i "regex\|parse error"
```

## Common Error Messages and Fixes

### Error: "Invalid regular expression: Invalid group"
**Cause**: Complex capture groups with non-greedy quantifiers

**Fix**: Simplify the regex, remove `.*?` patterns, use simple alternation

### Error: "error parsing regexp: invalid nested repetition operator"
**Cause**: Nested quantifiers like `(a+)+`

**Fix**: Simplify quantifiers, avoid nesting

### Error: "parse error: unexpected character"
**Cause**: Incorrect escaping in JSON/YAML

**Fix**: Use proper escaping: `\\` for backslash in JSON strings

## Updated Datasource Configuration

The Loki datasource derived fields have been updated with RE2-compatible patterns:

```yaml
derivedFields:
  # ✅ Simple error extraction (RE2-compatible)
  - name: "Error Context"
    matcherRegex: "(?i)(error|exception|failed)"
    url: "/explore?orgId=1&left=[\"now-1h\",\"now\",\"Loki\",{\"expr\":\"{} |~ \\\"(?i)(error|exception|failed)\\\"\"}]"
```

## Quick Reference Card

| Pattern Type | ❌ Avoid | ✅ Use Instead |
|-------------|---------|---------------|
| Error detection | `.*?(\w+Error)` | `(error\|exception)` |
| Multi-line | `pattern.*\n.*next` | Use separate filters |
| Named groups | `(?P<name>...)` | `(...)` (numbered) |
| Lookahead | `(?=pattern)` | Not needed in Loki |
| Backreference | `(\\w+).*\\1` | Not supported |
| Case-insensitive | Mix of patterns | `(?i)` at start |

## Additional Resources

- Loki LogQL documentation: https://grafana.com/docs/loki/latest/logql/
- RE2 syntax: https://github.com/google/re2/wiki/Syntax
- Grafana Loki examples: https://grafana.com/docs/loki/latest/logql/query_examples/
