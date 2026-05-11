import {
  createContext,
  type Dispatch,
  type SetStateAction,
  useContext,
} from 'react';

type CodeBlockContextType = {
  code: string;
  expandable: boolean;
  expanded: boolean;
  setExpandable: (expandable: boolean) => void;
  setExpanded: Dispatch<SetStateAction<boolean>>;
};

export const CodeBlockContext = createContext<CodeBlockContextType>({
  code: '',
  expandable: false,
  expanded: false,
  setExpandable: () => {},
  setExpanded: () => {},
});

export const useCodeBlockContext = () => useContext(CodeBlockContext);
