import reader from '../src/reader.ts';
export default { fetch(request, _env, ctx) {
  return reader.fetch(request, { PUBLIC_STATUS: { get() { throw new Error('PRIVATE_EXCEPTION_MUST_NOT_LEAK'); } } }, ctx);
} };
