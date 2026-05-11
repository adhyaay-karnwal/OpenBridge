import { ChevronUpChevronDownSFSymbolRegular } from '@/assets/sf-symbols/regular/chevron.up.chevron.down';
import { useCodeBlockContext } from './context';

export const CodeBlockCollapseButton = () => {
  const { expandable, setExpanded } = useCodeBlockContext();

  return expandable ? (
    <button
      onClick={() => setExpanded(v => !v)}
      className="size-5.5 flex-center icon-button opacity-85"
      type="button"
      title="Toggle expand/collapse"
    >
      <ChevronUpChevronDownSFSymbolRegular className="text-[14px]" />
    </button>
  ) : null;
};
