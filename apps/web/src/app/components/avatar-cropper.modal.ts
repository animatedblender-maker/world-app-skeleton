import { Component, EventEmitter, Input, Output } from '@angular/core';
import { CommonModule } from '@angular/common';
import { ImageCropperComponent, ImageCroppedEvent } from 'ngx-image-cropper';

@Component({
  selector: 'app-avatar-cropper-modal',
  standalone: true,
  imports: [CommonModule, ImageCropperComponent],
  template: `
    <div class="overlay" (click)="close()">
      <div class="modal" (click)="$event.stopPropagation()">
        <image-cropper
          [imageFile]="file"
          [maintainAspectRatio]="true"
          [aspectRatio]="1"
          [resizeToWidth]="512"
          format="png"
          [imageQuality]="92"
          (imageCropped)="onCropped($event)">
        </image-cropper>

        <button class="save" (click)="save()">SAVE</button>
      </div>
    </div>
  `,
  styles: [`
    .overlay{
      position:fixed; inset:0;
      background:rgba(0,0,0,.65);
      display:grid; place-items:center;
      z-index:1000;
    }
    .modal{
      width:360px;
      background:rgba(10,12,20,.92);
      border-radius:22px;
      padding:14px;
      box-shadow:0 30px 80px rgba(0,0,0,.55);
      backdrop-filter:blur(14px);
    }
    .save{
      margin-top:12px;
      width:100%;
      border-radius:16px;
      padding:12px;
      border:0;
      cursor:pointer;
      font-weight:900;
      letter-spacing:.14em;
      background:linear-gradient(90deg,#00ffd1,#8c00ff);
      color:#06080e;
    }
  `],
})
export class AvatarCropperModalComponent {
  @Input() file!: File;
  @Output() done = new EventEmitter<Blob>();
  @Output() closed = new EventEmitter<void>();

  private blob?: Blob;

  onCropped(e: ImageCroppedEvent) {
    if (e.blob) this.blob = e.blob;
  }

  save() {
    if (this.blob) this.done.emit(this.blob);
    this.close();
  }

  close() {
    this.closed.emit();
  }
}
