import { Component, inject, signal } from '@angular/core';
import { FormBuilder, ReactiveFormsModule, Validators } from '@angular/forms';
import { Router } from '@angular/router';
import { AuthService } from '../core/auth.service';
import { ForumApi } from '../core/forum-api';

@Component({
  selector: 'app-login',
  imports: [ReactiveFormsModule],
  templateUrl: './login.component.html',
})
export class LoginComponent {
  private readonly api = inject(ForumApi);
  private readonly auth = inject(AuthService);
  private readonly router = inject(Router);
  private readonly forms = inject(FormBuilder);

  readonly error = signal<string | null>(null);
  readonly form = this.forms.nonNullable.group({
    email: ['alex@example.com', Validators.required],
    password: ['password', Validators.required],
  });

  submit(): void {
    if (this.form.invalid) return;
    const { email, password } = this.form.getRawValue();
    this.api.login(email, password).subscribe({
      next: (session) => {
        this.auth.setSession(session);
        void this.router.navigateByUrl('/events');
      },
      error: () => this.error.set('Invalid email or password'),
    });
  }
}
