import { useState } from "react";

// `controlled` is an opt-in escape hatch: most callers just want a page
// number that's fine to lose on unmount, and get their own useState. A
// caller that needs its page to survive unmount (e.g. a persisted-state
// hook) passes its own state + setter here instead — usePagination still
// owns the clamping math either way, so "controlled" never means "reimplement
// this hook at the call site."
export function usePagination<T>(
  items: T[],
  pageSize: number,
  controlled?: { page: number; onPageChange: (page: number) => void },
) {
  const [localPage, setLocalPage] = useState(0);
  const page = controlled?.page ?? localPage;
  const setPage = controlled?.onPageChange ?? setLocalPage;
  const totalPages = Math.max(1, Math.ceil(items.length / pageSize));
  const safePage = Math.min(page, totalPages - 1);
  const pageItems = items.slice(safePage * pageSize, (safePage + 1) * pageSize);
  return { page: safePage, totalPages, pageItems, setPage };
}
