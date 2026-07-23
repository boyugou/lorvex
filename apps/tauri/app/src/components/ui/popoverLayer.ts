export type PopoverLayer = 'popover' | 'modalPopover';

interface PopoverLayerClasses {
  root: string;
  backdrop: string;
  panel: string;
}

const POPOVER_LAYER_CLASSES: Record<PopoverLayer, PopoverLayerClasses> = {
  popover: {
    root: 'z-[var(--z-popover)]',
    backdrop: 'z-[calc(var(--z-popover)-1)]',
    panel: 'z-[var(--z-popover)]',
  },
  modalPopover: {
    root: 'z-[calc(var(--z-modal)+1)]',
    backdrop: 'z-[calc(var(--z-modal)+1)]',
    panel: 'z-[calc(var(--z-modal)+2)]',
  },
};

export function getPopoverLayerClasses(layer: PopoverLayer): PopoverLayerClasses {
  return POPOVER_LAYER_CLASSES[layer];
}
