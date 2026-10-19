import { provideHttpClient } from '@angular/common/http';
import { HttpTestingController, provideHttpClientTesting } from '@angular/common/http/testing';
import { TestBed } from '@angular/core/testing';
import { ForumApi } from './forum-api';

describe('ForumApi', () => {
  it('requests upcoming events with the search filters', () => {
    TestBed.configureTestingModule({
      providers: [provideHttpClient(), provideHttpClientTesting()],
    });
    const api = TestBed.inject(ForumApi);
    const http = TestBed.inject(HttpTestingController);

    api.events({ q: 'housing', topicId: '4', location: 'Berlin' }).subscribe();

    const request = http.expectOne((candidate) => candidate.url === 'http://localhost:3000/api/events');
    expect(request.request.params.get('q')).toBe('housing');
    expect(request.request.params.get('topic_id')).toBe('4');
    expect(request.request.params.get('location')).toBe('Berlin');
    request.flush({ data: [] });
    http.verify();
  });

  it('cancels a registration by event id', () => {
    TestBed.configureTestingModule({
      providers: [provideHttpClient(), provideHttpClientTesting()],
    });
    const api = TestBed.inject(ForumApi);
    const http = TestBed.inject(HttpTestingController);

    api.cancelRegistration(6).subscribe();

    const request = http.expectOne('http://localhost:3000/api/registrations/cancel');
    expect(request.request.method).toBe('POST');
    expect(request.request.body).toEqual({ event_id: 6 });
    request.flush({ id: 1, status: 'cancelled', event_id: 6, event: { id: 6, title: 'Clinic', starts_at: '', location: 'Online' } });
    http.verify();
  });
});
