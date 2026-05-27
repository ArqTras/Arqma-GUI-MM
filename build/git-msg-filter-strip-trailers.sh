#!/bin/sh
perl -ne 'print unless /^\s*co-authored-by:/i || /^\s*made[-\s]*with\s*:?\s*cursor/i || /cursoragent@cursor\.com/i || /^\s*signed-off-by:\s*cursor/i || (/\banysphere\b/i && /-by:/i)'
