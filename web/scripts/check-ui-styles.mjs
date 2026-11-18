import assert from 'node:assert/strict';
import { cx } from '../src/components/ui/types.ts';
import { controlSizes, fieldControl, fieldFrame, fieldTones, focus, toneVariables } from '../src/components/ui/styles.ts';

// Regressions at the public className boundary: defaults must remain overridable
// without losing disabled, readonly, invalid or keyboard focus rules.
const field=cx(fieldControl,controlSizes.md,fieldTones.error,'w-40 rounded-control');
assert.ok(field.includes('w-40') && !field.split(' ').includes('w-full'));
assert.ok(field.includes('rounded-control') && !field.includes('rounded-field'));
assert.ok(field.includes('disabled:bg-panel') && field.includes('[&[readonly]:enabled]:bg-panel'));
assert.ok(field.includes('[--tt-field-focus:var(--danger)]'));
assert.ok(field.includes('focus-visible:outline-[length:var(--tt-focus-width)]'));
const frame=cx(fieldFrame,'flex gap-4');
assert.ok(frame.includes('flex') && !frame.split(' ').includes('grid'));
assert.ok(frame.includes('gap-4') && !frame.split(' ').includes('gap-2'));
const action=cx(controlSizes.md,focus,'h-auto min-h-11 px-4','px-0');
assert.ok(action.includes('h-auto') && !action.includes('h-(--tt-control-md)'));
assert.ok(action.includes('px-0') && !action.includes('px-4'));
assert.ok(action.includes('focus-visible:outline-accent'));
assert.ok(cx(toneVariables.neutral,toneVariables.error).includes('[--tt-tone-fg:var(--danger-ink)]'));
assert.ok(!cx(toneVariables.neutral,toneVariables.error).includes('[--tt-tone-fg:var(--muted)]'));
console.log('PASS: component class overrides preserve semantic state and focus variants.');
