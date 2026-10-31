import { Component, Input } from '@angular/core';

/**
 * iOS `MatteryaVerifiedBadge` — warm bronze scalloped seal + white check.
 * Default fill `#96713F` (`--m-verified-mark`).
 */
@Component({
  selector: 'app-verified-badge',
  standalone: true,
  template: `
    <span
      class="verified-badge"
      role="img"
      [attr.aria-label]="ariaLabel"
      [attr.title]="ariaLabel"
    >
      <svg
        viewBox="0 0 24 24"
        [attr.width]="size"
        [attr.height]="size"
        aria-hidden="true"
      >
        <path
          class="scallop"
          [attr.fill]="color"
          d="M12 1.5L14.8 3.1L18 3.4L19 6.5L21.7 8.3L21 11.5L21.7 14.7L19 16.5L18 19.6L14.8 19.9L12 22.5L9.2 20.9L6 20.6L5 17.5L2.3 15.7L3 12.5L2.3 9.3L5 6.5L6 3.4L9.2 3.1Z"
        />
        <path
          class="check"
          fill="none"
          stroke="#FFFFFF"
          stroke-width="2.6"
          stroke-linecap="round"
          stroke-linejoin="round"
          d="M7.3 12.1L10.4 15.1L16.8 8.5"
        />
      </svg>
    </span>
  `,
  styles: [
    `
      :host {
        display: inline-flex;
        align-items: center;
        justify-content: center;
        flex-shrink: 0;
        line-height: 0;
      }
      .verified-badge {
        display: inline-flex;
        align-items: center;
        justify-content: center;
        line-height: 0;
      }
      svg {
        display: block;
        flex-shrink: 0;
      }
    `,
  ],
})
export class VerifiedBadgeComponent {
  @Input() size = 20;
  @Input() color = 'var(--m-verified-mark, #96713F)';
  @Input() ariaLabel = 'Verified account';
}
