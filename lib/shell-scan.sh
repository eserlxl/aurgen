#!/bin/bash
# Scan shell scripts for command invocations outside strings, comments, and data
# Copyright © 2025 Eser KUBALI <lxldev.contact@gmail.com>
# SPDX-License-Identifier: GPL-3.0-or-later

# This file is part of AURGen project and is licensed under
# the GNU General Public License v3.0 or later.
# See the LICENSE file in the project root for details.

# Prevent direct execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "This script is a library and must be sourced, not executed." >&2
    exit 1
fi

set -euo pipefail

[[ -n "${AURGEN_SHELL_SCAN_SH_LOADED:-}" ]] && return 0
AURGEN_SHELL_SCAN_SH_LOADED=1

_is_shell_keyword() {
    case "$1" in
        if|then|else|elif|fi|for|while|until|do|done|case|"esac"|in|function|select|time|coproc|!|"{"|"}")
            return 0
            ;;
    esac
    return 1
}

_shell_push_frame() {
    local -n _pf_kind="$1" _pf_test="$2" _pf_arith="$3" _pf_depth="$4" _pf_case="$5" _pf_at="$6"
    _pf_kind+=("$7")
    _pf_test+=(0)
    _pf_arith+=(0)
    _pf_depth+=("$8")
    _pf_case+=(0)
    _pf_at+=("$9")
}

_shell_pop_frame() {
    # shellcheck disable=SC2034 # nameref array elements popped via unset -v
    local -n _pp_kind="$1" _pp_test="$2" _pp_arith="$3" _pp_depth="$4" _pp_case="$5" _pp_at="$6"
    unset -v '_pp_kind[-1]' '_pp_test[-1]' '_pp_arith[-1]' '_pp_depth[-1]' '_pp_case[-1]' '_pp_at[-1]'
}

_shell_refresh_case_pattern() {
    # shellcheck disable=SC2034 # _rcp_src/_rcp_pending/_rcp_depth/_rcp_arm nameref-accessed by _shell_apply_case
    local _rcp_src="$1" _rcp_depth="$4" _rcp_pending=0 _rcp_arm="$5"
    local -n _rcp_dst="$2"
    local -n _rcp_in_pat="$3"
    local -n _rcp_out_depth="$6"
    local -n _rcp_out_arm="$7"
    _shell_apply_case _rcp_src _rcp_dst _rcp_depth _rcp_pending _rcp_arm
    _rcp_in_pat=$(( _rcp_depth > 0 && _rcp_arm ))
    _rcp_out_depth=$_rcp_depth
    _rcp_out_arm=$_rcp_arm
}

# Text of one source line that is outside quotes. A single quote that stays open
# across lines hides the following lines: an embedded awk program is not a
# command list. Single-quote parity ignores double-quoted text and a
# backslash-escaped quote. $(...) stays visible in or out of double quotes, and
# backticks inside double quotes stay visible: those commands run. Quotes in the
# body use the same rules, and a double-quoted opener resumes at its closer.
_shell_visible_line() {
    local LC_ALL=C
    local -n _sq=$1
    local -n _dq=$2
    local -n _vis=$3
    # Parallel stacks: p is a $(...) opened in double quotes, u an unquoted substitution,
    # b is a backtick one in double quotes, v outside them, s a plain subshell,
    # a is arithmetic opened in double quotes.
    # _sub_case counts open `case` blocks; only a case or esac in command
    # position changes it.
    # _sub_at is 1 when the next word there is a command. _sub_cont is 1 when
    # a trailing backslash joins this line to the next.
    local -n _kind=$4
    local -n _depth=$5
    local -n _sub_case=$6
    local -n _sub_at=$7
    local -n _sub_cont=$8
    local line="$9"
    # Test and arithmetic state have a base frame and one entry per substitution or subshell.
    local -n _test=${10}
    local -n _arith=${11}
    local -a _frame_refs=("$4" "${10}" "${11}" "$5" "$6" "$7")
    local in_pattern=$(( ${12} > 0 && ${13} ))
    local -n _heredoc_line=${14}
    _heredoc_line="$line"
    local pattern_src pattern_dst pattern_depth pattern_arm
    local i c out="" esc=0
    local len=${#line}
    local case_subshell
    local subshell_open='(^|;|\|\||\||&&|\(|!|\{)[[:space:]]*((if|elif|while|until|then|else|do)[[:space:]]+)?(![[:space:]]+)?$'
    local pattern_close='\)[[:space:]]*$'
    local case_subshell_open='(^|;|[[:space:]]in)[[:space:]]*$'
    # A newline separates commands inside $(...). A continued line does not.
    if (( ! _sq && ! _dq && ! _sub_cont && ${#_kind[@]} )); then
        if [[ "${_kind[-1]}" == p || "${_kind[-1]}" == u || "${_kind[-1]}" == s ]]; then
            _sub_at[-1]=1
        fi
    fi
    for (( i=0; i<len; i++ )); do
        c="${line:i:1}"
        if (( esc )); then
            esc=0
            if (( ! _sq && ! _dq )); then
                out+="$c"
            fi
            continue
        fi
        if (( _sq )); then
            # Inside single quotes a backslash is literal; only ' ends the string.
            if [[ "$c" == "'" ]]; then
                _sq=0
            fi
            continue
        fi
        # shellcheck disable=SC2016 # literal $(( text
        if [[ "${line:i:3}" == '$((' ]]; then
            if (( _dq )); then
                _shell_push_frame "${_frame_refs[@]}" a 0 0
                _dq=0
            fi
            _arith[-1]=$((_arith[-1] + 2))
            out+=' '
            i=$((i + 2))
            continue
        fi
        if (( _dq )); then
            if [[ "$c" == "\\" ]]; then
                esc=1
                continue
            fi
            if [[ "$c" == '"' ]]; then
                _dq=0
                continue
            fi
            if [[ "$c" == '$' && "${line:i+1:1}" == '(' ]]; then
                out+="\$("
                i=$((i + 1))
                _shell_push_frame "${_frame_refs[@]}" p 1 1
                _dq=0
            elif [[ "$c" == '`' ]]; then
                out+='`'
                _shell_push_frame "${_frame_refs[@]}" b 0 0
                _dq=0
            fi
            continue
        fi
        if (( _arith[-1] > 0 )); then
            if [[ "$c" == '#' ]] && { (( i == 0 )) || [[ "${line:i-1:1}" == [[:space:]] ]]; }; then
                break
            fi
            # Keep raw delimiter quoting, but hide arithmetic operators from heredoc scanning.
            if [[ "$c" == '<' ]]; then
                _heredoc_line="${_heredoc_line:0:i} ${_heredoc_line:i+1}"
            fi
            case "$c" in
                '(') _arith[-1]=$((_arith[-1] + 1)) ;;
                ')')
                    _arith[-1]=$((_arith[-1] - 1))
                    if (( ! _arith[-1] && ${#_kind[@]} )) && [[ "${_kind[-1]}" == a ]]; then
                        _shell_pop_frame "${_frame_refs[@]}"
                        _dq=1
                    fi
                    ;;
            esac
            # shellcheck disable=SC2016 # literal $( text
            if [[ "$c" != '`' && "${line:i:2}" != '$(' ]]; then
                out+=' '
                continue
            fi
        elif [[ "${line:i:2}" == '((' ]] && (( ! _test[-1] )); then
            _arith[-1]=2
            out+=' '
            i=$((i + 1))
            continue
        fi
        if [[ "${line:i:2}" == '[[' ]]; then
            _test[-1]=1
        elif [[ "${line:i:2}" == ']]' ]] \
            && { (( i == 0 )) || [[ "${line:i-1:1}" == [[:space:]] ]]; }; then
            _test[-1]=0
        fi
        if (( _test[-1] )); then
            case "$c" in
                '|'|'('|')') out+=" "; continue ;;
            esac
        fi
        if [[ "${line:i:2}" == ';;' || "${line:i:2}" == ';&' ]] \
            || { (( in_pattern )) \
                && [[ "${line:i:4}" == 'esac' && "${line:i+4:1}" != [A-Za-z0-9_] ]] \
                && [[ "${line:0:i}" =~ $subshell_open ]]; }; then
            pattern_src="$out"
            # Include the terminator itself: after ;; a pattern follows, after esac an arm body may.
            if [[ "${line:i:4}" == 'esac' ]]; then
                pattern_src+='esac'
            else
                # A space keeps a ";" already in the text (a closed substitution) from merging into ";;;".
                pattern_src+=" ${line:i:2}"
            fi
            _shell_refresh_case_pattern "$pattern_src" pattern_dst in_pattern "${12}" "${13}" pattern_depth pattern_arm
        fi
        case_subshell=0
        if [[ "$c" == '(' && "$out" =~ $pattern_close ]]; then
            _shell_refresh_case_pattern "$out" pattern_dst in_pattern "${12}" "${13}" pattern_depth pattern_arm
            if (( pattern_depth > 0 && ! pattern_arm )) && [[ "$pattern_dst" =~ $case_subshell_open ]]; then
                case_subshell=1
            fi
        fi
        # Only command-position parentheses are subshells; array and test data stay literal.
        if [[ "$c" == '(' && "${line:i+1:1}" != '(' ]] \
            && { (( i == 0 )) || [[ "${line:i-1:1}" != '(' ]]; } \
            && (( ! _test[-1] && ! _arith[-1] && ! in_pattern )) \
            && { (( case_subshell )) || [[ "${line:0:i}" =~ $subshell_open ]]; }; then
            _shell_push_frame "${_frame_refs[@]}" s 1 1
            # Separate a same-line arm body from its case header.
            (( case_subshell )) && out+=';'
            out+="$c"
            continue
        fi
        [[ "$c" == ')' ]] && in_pattern=0
        if (( ${#_kind[@]} )); then
            if [[ "${_kind[-1]}" == p || "${_kind[-1]}" == u || "${_kind[-1]}" == s ]]; then
                # Command position: right after $(, or after ; && || | ( or a
                # newline, with only spaces between. An argument is not a command.
                # shortcut: case after if/then/else/do/{, an assignment prefix, or a
                # pattern ")" is not counted; upgrade when that command is a real dependency.
                if [[ "$c" == [[:space:]] ]]; then
                    :
                elif [[ "$c" == ';' || "$c" == '|' || "$c" == '(' ]]; then
                    _sub_at[-1]=1
                elif [[ "$c" == '&' && "${line:i+1:1}" == '&' ]]; then
                    _sub_at[-1]=1
                elif (( i > 0 )) && [[ "$c" == '&' && "${line:i-1:1}" == '&' ]]; then
                    _sub_at[-1]=1
                elif [[ "$c" == "\\" ]] && (( i + 1 == len )); then
                    :
                else
                    if (( _sub_at[-1] == 1 )) \
                        && { (( i == 0 )) || [[ "${line:i-1:1}" != [A-Za-z0-9_] ]]; } \
                        && { (( i + 4 == len )) || [[ "${line:i+4:1}" != [A-Za-z0-9_] ]]; }; then
                        if [[ "${line:i:4}" == "case" ]]; then
                            _sub_case[-1]=$((_sub_case[-1] + 1))
                        elif [[ "${line:i:4}" == "esac" ]] && (( _sub_case[-1] > 0 )); then
                            _sub_case[-1]=$((_sub_case[-1] - 1))
                        fi
                    fi
                    _sub_at[-1]=0
                fi
                if [[ "$c" == '(' ]]; then
                    if (( _sub_case[-1] == 0 )); then
                        _depth[-1]=$((_depth[-1] + 1))
                    fi
                    out+="$c"
                    continue
                fi
                if [[ "$c" == ')' ]]; then
                    if (( _sub_case[-1] > 0 )); then
                        out+="$c"
                        continue
                    fi
                    _depth[-1]=$((_depth[-1] - 1))
                    if (( _depth[-1] == 0 )); then
                        # p resumes the double quotes it suspended; u stays outside them.
                        if [[ "${_kind[-1]}" == p ]]; then
                            _dq=1
                        fi
                        _shell_pop_frame "${_frame_refs[@]}"
                        # Ends the body's segment: x"$(date)" jq runs jq, not date jq.
                        out+=";"
                    else
                        # Keep inner parentheses visible so multi-line array literals can end.
                        out+="$c"
                    fi
                    continue
                fi
            elif [[ ( "${_kind[-1]}" == b || "${_kind[-1]}" == v ) && "$c" == '`' ]]; then
                [[ "${_kind[-1]}" == b ]] && _dq=1
                _shell_pop_frame "${_frame_refs[@]}"
                out+=";"
                continue
            fi
        fi
        if [[ "$c" == "\\" ]]; then
            esc=1
            out+="$c"
            continue
        fi
        if [[ "$c" == "'" ]]; then
            _sq=1
            continue
        fi
        if [[ "$c" == '"' ]]; then
            _dq=1
            continue
        fi
        # A comment starts only at a word start: $((10#x)) and a#b are not comments.
        if [[ "$c" == '#' ]] && { (( i == 0 )) || [[ "${line:i-1:1}" == [[:space:]\;\&\|\(] ]]; }; then
            break
        fi
        if [[ "$c" == '`' ]]; then
            out+="$c"
            _shell_push_frame "${_frame_refs[@]}" v 0 0
            continue
        fi
        # Process substitutions use $( as a segment opener; each opener gets a frame.
        if [[ "${line:i+1:1}" == '(' ]] \
            && { [[ "$c" == '$' ]] \
                || { [[ "$c" == '<' || "$c" == '>' ]] && (( ! _arith[-1] && ! in_pattern )); }; }; then
            out+="\$("
            i=$((i + 1))
            _shell_push_frame "${_frame_refs[@]}" u 1 1
            continue
        fi
        out+="$c"
    done
    if (( esc && ! _sq && ! _dq )); then
        _sub_cont=1
    else
        _sub_cont=0
    fi
    _vis="$out"
}

# Drop one leading case pattern from a visible line, or return the line unchanged
# when it is a command. The first ')' ends the pattern. A ')' inside quotes, $(...)
# or $((...)) does not. _shell_visible_line already rewrites the closing ')' of
# $(...) to ';'.
# shortcut: that ';' also ends the substitution, so a ';' inside $(...) does too;
# upgrade if a case pattern contains a semicolon inside $(...).
_shell_without_case_pattern() {
    local s="$1"
    local i=0 j c
    local len=${#s}
    local sub=0 sq=0 dq=0
    while (( i < len )) && [[ "${s:i:1}" == [[:space:]] ]]; do
        i=$((i + 1))
    done
    if (( i >= len )); then
        printf '%s' "$s"
        return 0
    fi
    j=$i
    if [[ "${s:j:1}" == '(' ]]; then
        j=$((j + 1))
    fi
    while (( j < len )); do
        c="${s:j:1}"
        if (( sq )); then
            [[ "$c" == "'" ]] && sq=0
            j=$((j + 1))
            continue
        fi
        if (( dq )); then
            [[ "$c" == '"' ]] && dq=0
            j=$((j + 1))
            continue
        fi
        if (( sub > 0 )); then
            if [[ "$c" == '(' ]]; then
                sub=$((sub + 1))
            elif [[ "$c" == ')' ]]; then
                sub=$((sub - 1))
            elif [[ "$c" == ';' ]]; then
                sub=0
            fi
            j=$((j + 1))
            continue
        fi
        if [[ "$c" == '$' && "${s:j+1:1}" == '(' ]]; then
            sub=$((sub + 1))
            j=$((j + 2))
            continue
        fi
        if [[ "$c" == "'" ]]; then
            sq=1
            j=$((j + 1))
            continue
        fi
        if [[ "$c" == '"' ]]; then
            dq=1
            j=$((j + 1))
            continue
        fi
        # ';;' before ')' is the next arm, not part of a leading pattern.
        if [[ "$c" == ';' && "${s:j+1:1}" == ';' ]]; then
            printf '%s' "$s"
            return 0
        fi
        if [[ "$c" == ')' ]]; then
            printf '%s' "${s:j+1}"
            return 0
        fi
        j=$((j + 1))
    done
    printf '%s' "$s"
}

# Word-bounded case/in/esac on one visible line. Patterns are removed; the
# commands after ')' stay. case_depth counts bodies opened by in, and case_arm
# marks where the next arm pattern may start (after in or ;;, ;&, ;;&).
# Called in the current shell: a command substitution would drop the depth.
_shell_apply_case() {
    local -n _src=$1
    local -n _dst=$2
    local -n _case_depth=$3
    local -n _pending=$4
    local -n _arm=$5
    local out="" rest word next
    rest="$_src"
    while [[ -n "$rest" ]]; do
        if [[ "$rest" == [[:space:]]* ]]; then
            out+="${rest:0:1}"
            rest="${rest:1}"
            continue
        fi
        if (( _case_depth > 0 && _arm )) && [[ "$rest" != 'esac'* || "${rest:4:1}" == [A-Za-z0-9_] ]]; then
            next="$(_shell_without_case_pattern "$rest")"
            if [[ "$next" != "$rest" ]]; then
                _arm=0
                rest="$next"
                continue
            fi
        fi
        if [[ "$rest" == ';;&'* ]]; then
            out+=";;"
            rest="${rest:3}"
            (( _case_depth > 0 )) && _arm=1
            continue
        fi
        if [[ "$rest" == ';;'* || "$rest" == ';&'* ]]; then
            out+=";"
            rest="${rest:2}"
            (( _case_depth > 0 )) && _arm=1
            continue
        fi
        if [[ "$rest" != [A-Za-z0-9_]* ]]; then
            _arm=0
            out+="${rest:0:1}"
            rest="${rest:1}"
            continue
        fi
        word="${rest%%[^A-Za-z0-9_]*}"
        _arm=0
        case "$word" in
            case) _pending=$((_pending + 1)) ;;
            in)
                if (( _pending > 0 )); then
                    _pending=$((_pending - 1))
                    _case_depth=$((_case_depth + 1))
                    _arm=1
                fi
                ;;
            "esac")
                if (( _case_depth > 0 )); then
                    _case_depth=$((_case_depth - 1))
                fi
                ;;
        esac
        out+="$word"
        rest="${rest:${#word}}"
    done
    _dst="$out"
}

# Heredoc delimiters opened on this raw line, outside quotes and comments.
# Quote state is the state at the start of the line. <<< is a here-string.
_shell_queue_heredocs() {
    local LC_ALL=C
    local line="$1"
    local sq="$2"
    local dq="$3"
    local -n _hd=$4
    local -n _tb=$5
    local i=0 c esc=0 tabs q delim
    local len=${#line}
    while (( i < len )); do
        c="${line:i:1}"
        if (( esc )); then
            esc=0
            i=$((i + 1))
            continue
        fi
        if (( sq )); then
            [[ "$c" == "'" ]] && sq=0
            i=$((i + 1))
            continue
        fi
        if (( dq )); then
            if [[ "$c" == "\\" ]]; then
                esc=1
                i=$((i + 1))
                continue
            fi
            if [[ "$c" == '"' ]]; then
                dq=0
            fi
            i=$((i + 1))
            continue
        fi
        if [[ "$c" == "\\" ]]; then
            esc=1
            i=$((i + 1))
            continue
        fi
        if [[ "$c" == "'" ]]; then
            sq=1
            i=$((i + 1))
            continue
        fi
        if [[ "$c" == '"' ]]; then
            dq=1
            i=$((i + 1))
            continue
        fi
        if [[ "$c" == '#' ]]; then
            break
        fi
        if [[ "$c" == '<' && "${line:i+1:1}" == '<' ]]; then
            if [[ "${line:i+2:1}" == '<' ]]; then
                i=$((i + 3))
                continue
            fi
            tabs=0
            q=""
            delim=""
            i=$((i + 2))
            if [[ "${line:i:1}" == '-' ]]; then
                tabs=1
                i=$((i + 1))
            fi
            while (( i < len )) && [[ "${line:i:1}" == [[:space:]] ]]; do
                i=$((i + 1))
            done
            if [[ "${line:i:1}" == "'" || "${line:i:1}" == '"' ]]; then
                q="${line:i:1}"
                i=$((i + 1))
            elif [[ "${line:i:1}" == "\\" ]]; then
                i=$((i + 1))
            fi
            if [[ -n "$q" ]]; then
                while (( i < len )); do
                    c="${line:i:1}"
                    [[ "$c" == "$q" ]] && break
                    delim+="$c"
                    i=$((i + 1))
                done
            else
                while (( i < len )); do
                    c="${line:i:1}"
                    [[ "$c" =~ [A-Za-z0-9_.-] ]] || break
                    delim+="$c"
                    i=$((i + 1))
                done
            fi
            if [[ -n "$q" && "${line:i:1}" == "$q" ]]; then
                i=$((i + 1))
            fi
            if [[ -n "$delim" ]]; then
                _hd+=("$delim")
                _tb+=("$tabs")
            fi
            continue
        fi
        i=$((i + 1))
    done
}

_shell_visible_lines() {
    local LC_ALL=C
    local file="$1"
    # namerefs: _shell_visible_line updates quote and substitution state here.
    # shellcheck disable=SC2034
    local line in_sq=0 in_dq=0 visible heredoc_line
    # shellcheck disable=SC2034
    local -a sub_kind=() sub_depth=() sub_case=() sub_at=() in_test=(0) in_arith=(0)
    # shellcheck disable=SC2034
    local sub_cont=0
    local -a hd_delim=() hd_tabs=()
    # shellcheck disable=SC2034 # namerefs: _shell_apply_case updates them
    local case_depth=0 case_pending=0 case_arm=0
    local sq0 dq0 cmp filtered in_array=0
    local array_open='[A-Za-z_][A-Za-z0-9_]*(\[[^]]*\])?\+?=\([^)]*$'
    while IFS= read -r line || [[ -n "$line" ]]; do
        if (( ${#hd_delim[@]} )); then
            cmp="$line"
            if [[ "${hd_tabs[0]}" == 1 ]]; then
                cmp="${cmp#"${cmp%%[!$'\t']*}"}"
            fi
            if [[ "$cmp" == "${hd_delim[0]}" ]]; then
                if (( ${#hd_delim[@]} > 1 )); then
                    hd_delim=("${hd_delim[@]:1}")
                    hd_tabs=("${hd_tabs[@]:1}")
                else
                    hd_delim=()
                    hd_tabs=()
                fi
            fi
            # shortcut: an unquoted delimiter hides the body whole, so $(...) in it is not a command; upgrade when here-document expansions must be scanned.
            continue
        fi
        sq0=$in_sq
        dq0=$in_dq
        _shell_visible_line in_sq in_dq visible sub_kind sub_depth sub_case sub_at sub_cont "$line" in_test in_arith "$case_depth" "$case_arm" heredoc_line
        _shell_apply_case visible filtered case_depth case_pending case_arm
        _shell_queue_heredocs "$heredoc_line" "$sq0" "$dq0" hd_delim hd_tabs
        # Elements of a multi-line array literal are data: `linux gnu unix` is not a command.
        # shortcut: a $(...) element of such an array is hidden too; upgrade if one must be scanned.
        if (( in_array )); then
            [[ "$filtered" == *')'* ]] && in_array=0
            printf '\n'
            continue
        fi
        if [[ "$filtered" =~ $array_open ]]; then
            in_array=1
            filtered="${filtered%"${BASH_REMATCH[0]}"}"
        fi
        printf '%s\n' "$filtered"
    done < "$file"
}

_shell_segments_of() {
    local line="$1"
    line="${line//$'\t'/ }"
    line="${line//||/$'\n'}"
    line="${line//&&/$'\n'}"
    line="${line//;/$'\n'}"
    line="${line//|/$'\n'}"
    line="${line//\`/$'\n'}"
    line="${line//\$\(/$'\n'}"
    printf '%s\n' "$line"
}

# Consume one separate option or positional argument from a segment that starts
# at the space before that argument. A quoted argument was already emptied by
# _shell_visible_line, leaving two adjacent spaces; dropping one space and any
# visible word up to the next space consumes either form.
_shell_skip_arg() {
    local -n _ssa_seg=$1
    if [[ "$_ssa_seg" == [[:space:]]* ]]; then
        _ssa_seg="${_ssa_seg:1}"
        _ssa_seg="${_ssa_seg#"${_ssa_seg%%[[:space:]]*}"}"
    fi
}

# Assignments, keywords, command wrappers and their options, and one leading "("
# removed, so the first word of each emitted line is a command.
_shell_command_text() {
    local LC_ALL=C
    local segment="$1"
    local word wrapper rest is_query
    segment="${segment#"${segment%%[![:space:]]*}"}"
    [[ -z "$segment" ]] && return 0
    while true; do
        if [[ "$segment" =~ ^[A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+(.+)$ ]]; then
            segment="${BASH_REMATCH[1]}"
            segment="${segment#"${segment%%[![:space:]]*}"}"
            [[ -z "$segment" ]] && return 0
            continue
        fi
        # One "(" opens a subshell (cd dir && tar xf a.tar). "((" stays arithmetic.
        if [[ "$segment" == '('* && "$segment" != '(('* ]]; then
            segment="${segment:1}"
            segment="${segment#"${segment%%[![:space:]]*}"}"
            [[ -z "$segment" ]] && return 0
            continue
        fi
        word="${segment%%[[:space:]]*}"
        # The word after for/select is a loop variable (for file in ...), never a command.
        case "$word" in
            for|select) return 0 ;;
        esac
        # exec replaces the shell. Skip it and -a NAME, -c, -l, and -- so the next
        # word is the command. A redirection-only exec runs nothing new.
        if [[ "$word" == exec ]]; then
            segment="${segment#"$word"}"
            segment="${segment#"${segment%%[![:space:]]*}"}"
            while [[ -n "$segment" ]]; do
                word="${segment%%[[:space:]]*}"
                case "$word" in
                    -c|-l|-cl|-lc)
                        segment="${segment#"$word"}"
                        segment="${segment#"${segment%%[![:space:]]*}"}"
                        ;;
                    -a)
                        segment="${segment#"$word"}"
                        _shell_skip_arg segment
                        segment="${segment#"${segment%%[![:space:]]*}"}"
                        ;;
                    -a?*)
                        segment="${segment#"$word"}"
                        segment="${segment#"${segment%%[![:space:]]*}"}"
                        ;;
                    --)
                        segment="${segment#"$word"}"
                        segment="${segment#"${segment%%[![:space:]]*}"}"
                        break
                        ;;
                    *)
                        break
                        ;;
                esac
            done
            [[ -z "$segment" ]] && return 0
            word="${segment%%[[:space:]]*}"
            case "$word" in
                *">"*|*"<"*) return 0 ;;
            esac
            continue
        fi
        # command runs its argument unless -v or -V turns it into a presence query.
        if [[ "$word" == command ]]; then
            rest="${segment#"$word"}"
            rest="${rest#"${rest%%[![:space:]]*}"}"
            is_query=0
            while [[ -n "$rest" ]]; do
                word="${rest%%[[:space:]]*}"
                if [[ "$word" == -- ]]; then
                    rest="${rest#"$word"}"
                    rest="${rest#"${rest%%[![:space:]]*}"}"
                    break
                elif [[ "$word" =~ ^-[pvV]*[vV][pvV]*$ ]]; then
                    is_query=1
                    break
                elif [[ "$word" == -* ]]; then
                    rest="${rest#"$word"}"
                    rest="${rest#"${rest%%[![:space:]]*}"}"
                else
                    break
                fi
            done
            (( is_query )) && break
            segment="$rest"
            [[ -z "$segment" ]] && return 0
            word="${segment%%[[:space:]]*}"
            case "$word" in
                *">"*|*"<"*) return 0 ;;
            esac
            continue
        fi
        case "$word" in
            nohup|nice|timeout|sudo|env|stdbuf|xargs)
                wrapper="$word"
                printf '%s\n' "$wrapper"
                segment="${segment#"$wrapper"}"
                if [[ "$wrapper" == timeout ]]; then
                    while [[ "$segment" =~ ^[[:space:]]+(-[^[:space:]]*) ]]; do
                        word="${BASH_REMATCH[1]}"
                        segment="${segment#"${segment%%[![:space:]]*}"}"
                        segment="${segment#"$word"}"
                        if [[ "$word" == -- ]]; then
                            break
                        elif [[ "$word" =~ ^-[fpv]*[ks]$ || "$word" == --kill-after || "$word" == --signal ]]; then
                            _shell_skip_arg segment
                        fi
                    done
                    _shell_skip_arg segment
                    segment="${segment#"${segment%%[![:space:]]*}"}"
                else
                    segment="${segment#"${segment%%[![:space:]]*}"}"
                    while [[ -n "$segment" ]]; do
                        word="${segment%%[[:space:]]*}"
                        if [[ "$word" == -- ]]; then
                            segment="${segment#"$word"}"
                            segment="${segment#"${segment%%[![:space:]]*}"}"
                            break
                        elif [[ "$wrapper" == nice && ( "$word" == -n || "$word" == --adjustment ) ]] \
                            || [[ "$wrapper" == sudo && ( "$word" =~ ^-[ABbEHhiKklnoPSsVv]*[ugCDRhprtTUac]$ || "$word" =~ ^--(user|group|close-from|chdir|chroot|host|prompt|role|type|command-timeout|other-user)$ ) ]] \
                            || [[ "$wrapper" == env && ( "$word" =~ ^-[i0v]*[uCSa]$ || "$word" =~ ^--(unset|chdir|split-string|argv0)$ ) ]] \
                            || [[ "$wrapper" == stdbuf && ( "$word" =~ ^-[ioe]$ || "$word" =~ ^--(input|output|error)$ ) ]] \
                            || [[ "$wrapper" == xargs && ( "$word" =~ ^-[0oprtix]*[adEILnPsSJ]$ || "$word" =~ ^--(arg-file|delimiter|eof|replace|max-lines|max-args|max-procs|max-chars|process-slot-var)$ ) ]]; then
                            segment="${segment#"$word"}"
                            _shell_skip_arg segment
                            segment="${segment#"${segment%%[![:space:]]*}"}"
                        elif [[ "$wrapper" == sudo && ( "$word" =~ ^-[ABbEHhiKklnoPSsVv]*e[ABbEHhiKklnoPSsVv]*$ || "$word" == --edit ) ]]; then
                            return 0
                        elif [[ ( "$wrapper" == sudo || "$wrapper" == env ) && "$word" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; then
                            segment="${segment#"$word"}"
                            segment="${segment#"${segment%%[![:space:]]*}"}"
                        elif [[ "$word" == -* ]]; then
                            segment="${segment#"$word"}"
                            segment="${segment#"${segment%%[![:space:]]*}"}"
                        else
                            break
                        fi
                    done
                fi
                [[ -z "$segment" ]] && return 0
                word="${segment%%[[:space:]]*}"
                case "$word" in
                    *">"*|*"<"*) return 0 ;;
                esac
                continue
                ;;
        esac
        _is_shell_keyword "$word" || break
        segment="${segment#"$word"}"
        segment="${segment#"${segment%%[![:space:]]*}"}"
        [[ -z "$segment" ]] && return 0
    done
    printf '%s\n' "$segment"
}

_shell_walk_segments() {
    local file="$1"
    local line segment
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "${line//[[:space:]]}" ]] && continue
        while IFS= read -r segment || [[ -n "$segment" ]]; do
            [[ -z "$segment" ]] && continue
            printf '%s\n' "$segment"
        done < <(_shell_segments_of "$line")
    done < <(_shell_visible_lines "$file")
}

# Command names in command position, one per line.
_shell_commands() {
    local LC_ALL=C
    local file="$1"
    local segment text line word
    while IFS= read -r segment || [[ -n "$segment" ]]; do
        text="$(_shell_command_text "$segment")"
        [[ -z "$text" ]] && continue
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            word="${line%%[[:space:]]*}"
            case "$word" in
                ''|-*) continue ;;
                *[!A-Za-z0-9._+-]*) continue ;;
            esac
            printf '%s\n' "$word"
        done <<< "$text"
    done < <(_shell_walk_segments "$file")
}

# Arguments of presence checks. Those tools are optional, not hard depends.
_shell_guarded_commands() {
    local LC_ALL=C
    local file="$1"
    local segment raw text word
    while IFS= read -r segment || [[ -n "$segment" ]]; do
        raw="$(_shell_command_text "$segment")"
        [[ -z "$raw" ]] && continue
        while IFS= read -r text; do
            [[ -z "$text" ]] && continue
            word="${text%%[[:space:]]*}"
            case "$word" in
                command)
                    # A presence query is any option cluster with v or V (-v, -V, -pv, -p -v),
                    # optionally ended by --, followed by the name.
                    local is_query=0
                    text="${text#"$word"}"
                    text="${text#"${text%%[![:space:]]*}"}"
                    while [[ "$text" == -* ]]; do
                        word="${text%%[[:space:]]*}"
                        if [[ "$word" == -- ]]; then
                            text="${text#--}"
                            text="${text#"${text%%[![:space:]]*}"}"
                            break
                        fi
                        [[ "$word" =~ ^-[pvV]+$ ]] || { is_query=0; break; }
                        [[ "$word" == *[vV]* ]] && is_query=1
                        text="${text#"$word"}"
                        text="${text#"${text%%[![:space:]]*}"}"
                    done
                    (( is_query )) || continue
                    word="${text%%[[:space:]]*}"
                    [[ "$word" =~ ^[A-Za-z0-9][A-Za-z0-9._+-]*$ ]] || continue
                    printf '%s\n' "$word"
                    ;;
                type)
                    text="${text#"$word"}"
                    text="${text#"${text%%[![:space:]]*}"}"
                    # -p is the usual spelling; -P and -a are the same presence check.
                    case "$text" in
                        -p|-p[[:space:]]*|-P|-P[[:space:]]*|-a|-a[[:space:]]*)
                            text="${text:2}"
                            ;;
                        *) continue ;;
                    esac
                    text="${text#"${text%%[![:space:]]*}"}"
                    while [[ -n "$text" ]]; do
                        word="${text%%[[:space:]]*}"
                        case "$word" in
                            -*|*[!A-Za-z0-9._+-]*) break ;;
                        esac
                        printf '%s\n' "$word"
                        text="${text#"$word"}"
                        text="${text#"${text%%[![:space:]]*}"}"
                    done
                    ;;
                hash|which)
                    text="${text#"$word"}"
                    text="${text#"${text%%[![:space:]]*}"}"
                    while [[ -n "$text" ]]; do
                        word="${text%%[[:space:]]*}"
                        case "$word" in
                            -*|*[!A-Za-z0-9._+-]*) break ;;
                        esac
                        printf '%s\n' "$word"
                        text="${text#"$word"}"
                        text="${text#"${text%%[![:space:]]*}"}"
                    done
                    ;;
            esac
        done <<< "$raw"
    done < <(_shell_walk_segments "$file")
}

# Print the names a script defines as functions (name(), name (), function name), one per line.
# A call to such a name runs the script's own function, not a command from a package.
# Usage: _shell_defined_functions <file>
_shell_defined_functions() {
    local LC_ALL=C segment
    # The walked segments already leave out comments, string contents, arithmetic and
    # heredoc bodies, so a "name() {" there is a real definition.
    local def_re='^[[:space:]]*(function[[:space:]]+)?([A-Za-z_][A-Za-z0-9_.:-]*)[[:space:]]*\(\)'
    local func_re='^[[:space:]]*function[[:space:]]+([A-Za-z_][A-Za-z0-9_.:-]*)([[:space:]]|\{|$)'
    while IFS= read -r segment || [[ -n "$segment" ]]; do
        if [[ "$segment" =~ $def_re ]]; then
            printf '%s\n' "${BASH_REMATCH[2]}"
        elif [[ "$segment" =~ $func_re ]]; then
            printf '%s\n' "${BASH_REMATCH[1]}"
        fi
    done < <(_shell_walk_segments "$1") | sort -u
}

