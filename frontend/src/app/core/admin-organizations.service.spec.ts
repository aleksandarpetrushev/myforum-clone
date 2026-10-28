import { provideHttpClient } from '@angular/common/http';
import { HttpTestingController, provideHttpClientTesting } from '@angular/common/http/testing';
import { TestBed } from '@angular/core/testing';
import { AdminOrganizationsService } from './admin-organizations.service';
import { AuthService } from './auth.service';

describe('AdminOrganizationsService', () => {
  const url = 'http://localhost:3000/api/me/organizations';
  let service: AdminOrganizationsService;
  let auth: AuthService;
  let http: HttpTestingController;

  beforeEach(() => {
    TestBed.configureTestingModule({ providers: [provideHttpClient(), provideHttpClientTesting()] });
    service = TestBed.inject(AdminOrganizationsService);
    auth = TestBed.inject(AuthService);
    http = TestBed.inject(HttpTestingController);
  });

  afterEach(() => http.verify());

  it("clears the previous user's organizations as soon as a different user signs in", () => {
    auth.token.set('admin-token');
    service.ensureLoaded();
    http.expectOne(url).flush({ data: [{ id: 1, name: 'Atlas' }] });
    expect(service.canCreate()).toBeTrue();

    auth.token.set('member-token');
    service.ensureLoaded();

    expect(service.organizations()).toEqual([]);
    expect(service.canCreate()).toBeFalse();
    http.expectOne(url).flush({ data: [] });
    expect(service.loaded()).toBeTrue();
  });

  it('ignores a reply that arrives for an earlier sign-in', () => {
    auth.token.set('admin-token');
    service.ensureLoaded();
    const stale = http.expectOne(url);

    auth.token.set('member-token');
    service.ensureLoaded();
    const current = http.expectOne(url);

    current.flush({ data: [] });
    stale.flush({ data: [{ id: 1, name: 'Atlas' }] });

    expect(service.organizations()).toEqual([]);
    expect(service.canCreate()).toBeFalse();
  });
});
