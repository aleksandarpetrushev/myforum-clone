import { TestBed } from '@angular/core/testing';
import { AuthService } from './auth.service';

describe('AuthService', () => {
  beforeEach(() => {
    localStorage.clear();
    TestBed.configureTestingModule({});
  });

  it('stores the session token', () => {
    const auth = TestBed.inject(AuthService);
    auth.setSession({
      token: 'abc',
      user: { id: 1, email: 'alex@example.com', name: 'Alex', location: 'Berlin' },
    });

    expect(auth.token()).toBe('abc');
    expect(auth.user()?.email).toBe('alex@example.com');
  });
});
